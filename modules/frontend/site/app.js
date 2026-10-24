// Presentation tier logic.
// Sign-in uses the OAuth 2.0 authorization code flow with PKCE against the
// Cognito hosted UI, then every API call sends the access token as a Bearer token.

const cfg = window.APP_CONFIG;
const $ = (id) => document.getElementById(id);

// ---------- Small helpers ----------

function base64url(bytes) {
  let text = "";
  new Uint8Array(bytes).forEach((b) => { text += String.fromCharCode(b); });
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeJwt(token) {
  const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(payload));
}

function getTokens() {
  try {
    const tokens = JSON.parse(sessionStorage.getItem("tokens"));
    if (!tokens) return null;
    // Treat the session as over once the access token expires
    if (decodeJwt(tokens.access_token).exp * 1000 < Date.now()) {
      sessionStorage.removeItem("tokens");
      return null;
    }
    return tokens;
  } catch (err) {
    return null;
  }
}

function showLastCall(method, path, status, body) {
  $("last-call").textContent = method + " " + path + "  ->  HTTP " + status + "\n" +
    (body === undefined ? "" : JSON.stringify(body, null, 2));
}

// ---------- Sign in / sign out ----------

async function signIn() {
  // PKCE: a random secret (verifier) stays in this tab; only its hash goes to Cognito.
  // Whoever exchanges the code must prove they hold the verifier.
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = base64url(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier)));
  const state = base64url(crypto.getRandomValues(new Uint8Array(16)));
  sessionStorage.setItem("pkce_verifier", verifier);
  sessionStorage.setItem("oauth_state", state);

  const params = new URLSearchParams({
    response_type: "code",
    client_id: cfg.clientId,
    redirect_uri: cfg.redirectUri,
    scope: "openid email profile",
    code_challenge_method: "S256",
    code_challenge: challenge,
    state: state,
  });
  window.location.assign(cfg.cognitoDomain + "/oauth2/authorize?" + params.toString());
}

function signOut() {
  sessionStorage.clear();
  const params = new URLSearchParams({ client_id: cfg.clientId, logout_uri: cfg.redirectUri });
  window.location.assign(cfg.cognitoDomain + "/logout?" + params.toString());
}

// After Cognito redirects back with ?code=..., trade the code for tokens
async function handleRedirect() {
  const query = new URLSearchParams(window.location.search);
  const code = query.get("code");
  if (!code) return;

  window.history.replaceState({}, "", "/"); // remove the code from the address bar

  if (query.get("state") !== sessionStorage.getItem("oauth_state")) {
    showLastCall("POST", "/oauth2/token", "not sent", { error: "State mismatch, sign-in ignored" });
    return;
  }

  const body = new URLSearchParams({
    grant_type: "authorization_code",
    client_id: cfg.clientId,
    code: code,
    redirect_uri: cfg.redirectUri,
    code_verifier: sessionStorage.getItem("pkce_verifier") || "",
  });

  const res = await fetch(cfg.cognitoDomain + "/oauth2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body,
  });
  const tokens = await res.json();
  sessionStorage.removeItem("pkce_verifier");
  sessionStorage.removeItem("oauth_state");

  if (!res.ok) {
    showLastCall("POST", "/oauth2/token", res.status, tokens);
    return;
  }
  sessionStorage.setItem("tokens", JSON.stringify(tokens));
}

// ---------- API calls ----------

async function api(method, path, payload) {
  const tokens = getTokens();
  if (!tokens) {
    render();
    return null;
  }

  const options = {
    method: method,
    headers: { Authorization: "Bearer " + tokens.access_token },
  };
  if (payload !== undefined) {
    options.headers["Content-Type"] = "application/json";
    options.body = JSON.stringify(payload);
  }

  const res = await fetch(cfg.apiUrl + path, options);
  let body;
  try { body = await res.json(); } catch (err) { body = undefined; }
  showLastCall(method, path, res.status, body);
  return res.ok ? body : null;
}

async function loadTasks() {
  const tasks = await api("GET", "/tasks");
  const list = $("task-list");
  list.replaceChildren();
  if (!tasks) return;

  $("empty").hidden = tasks.length > 0;
  tasks.forEach((task) => {
    const li = document.createElement("li");

    const text = document.createElement("div");
    text.textContent = task.title; // textContent, never innerHTML, so user input can't inject HTML
    const when = document.createElement("small");
    when.textContent = "Created " + new Date(task.createdAt * 1000).toLocaleString();
    text.appendChild(when);

    const del = document.createElement("button");
    del.type = "button";
    del.className = "secondary";
    del.textContent = "Delete";
    del.addEventListener("click", async () => {
      await api("DELETE", "/tasks/" + encodeURIComponent(task.taskId));
      loadTasks();
    });

    li.append(text, del);
    list.appendChild(li);
  });
}

// ---------- Page state ----------

function render() {
  const tokens = getTokens();
  const signedIn = Boolean(tokens);
  $("signed-in").hidden = !signedIn;
  $("signed-out").hidden = signedIn;
  $("login-btn").hidden = signedIn;
  $("logout-btn").hidden = !signedIn;
  $("user-email").textContent = signedIn ? decodeJwt(tokens.id_token).email : "";
  if (signedIn) loadTasks();
}

$("login-btn").addEventListener("click", signIn);
$("logout-btn").addEventListener("click", signOut);
$("task-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = $("task-title");
  const title = input.value.trim();
  if (!title) return;
  input.value = "";
  await api("POST", "/tasks", { title: title });
  loadTasks();
});

handleRedirect().catch((err) => showLastCall("POST", "/oauth2/token", "error", { error: String(err) }))
  .finally(render);
