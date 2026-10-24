# ---------- Private S3 bucket for the site files ----------

resource "aws_s3_bucket" "site" {
  bucket        = var.bucket_name
  force_destroy = true # lets terraform destroy remove the uploaded files too
}

# Nobody can read the bucket directly; only CloudFront can (see bucket policy below)
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------- CloudFront: HTTPS delivery from edge locations ----------

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.name}-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.name} frontend"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # North America and Europe edges only, cheapest

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed "CachingDisabled" policy, so file changes show up immediately during the lab.
    # A production site would use "CachingOptimized" and invalidate on deploy.
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowCloudFrontOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------- Site files ----------

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.site.id
  key          = "index.html"
  source       = "${path.module}/site/index.html"
  etag         = filemd5("${path.module}/site/index.html")
  content_type = "text/html"
}

resource "aws_s3_object" "app_js" {
  bucket       = aws_s3_bucket.site.id
  key          = "app.js"
  source       = "${path.module}/site/app.js"
  etag         = filemd5("${path.module}/site/app.js")
  content_type = "application/javascript"
}

resource "aws_s3_object" "styles" {
  bucket       = aws_s3_bucket.site.id
  key          = "styles.css"
  source       = "${path.module}/site/styles.css"
  etag         = filemd5("${path.module}/site/styles.css")
  content_type = "text/css"
}

# Settings the browser app needs. These are public values (no secrets):
# the API URL, the sign-in domain and the public app client ID.
resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.site.id
  key          = "config.js"
  content_type = "application/javascript"
  content = templatefile("${path.module}/site/config.js.tpl", {
    api_url        = var.api_url
    cognito_domain = var.cognito_domain
    client_id      = var.client_id
    redirect_uri   = "https://${aws_cloudfront_distribution.site.domain_name}/"
  })
}
