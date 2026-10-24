# galust-dev.ru

Personal site of Galust Arakelyan, DevOps engineer: blog, about and CV.

**Live:** https://galust-dev.ru

## How it works

- [Hugo](https://gohugo.io) with a hand-written layout, no theme and no JavaScript frameworks. Light and dark mode.
- The CV lives in one file, [`data/cv.yaml`](data/cv.yaml). Hugo renders it twice: as the [`/cv/`](https://galust-dev.ru/cv/) page and as a standalone print page.
- On every push to `main`, GitHub Actions:
  1. builds the site with a pinned Hugo version;
  2. prints the CV page to PDF with headless Chrome and fails if it runs past two pages;
  3. checks every internal link and asset;
  4. uploads the result to my own nginx server with rsync over SSH and smoke-tests the live URLs.

  Pull requests run the same checks without deploying.

## Hosting

A VPS with nginx and Let's Encrypt. [`deploy/setup-server.sh`](deploy/setup-server.sh) prepares it once: it backs up the nginx config, creates a `site-deploy` user whose SSH key can only run `rrsync -wo` into the web root (no shell, no reads, nothing outside the site), gets a certificate and installs [`deploy/nginx-site.conf`](deploy/nginx-site.conf) with HSTS, CSP and caching (fingerprinted CSS for a year, HTML revalidated). Every nginx change goes through `nginx -t`; a failing config is unlinked before it can affect other sites on the server.

CI needs three secrets — `DEPLOY_KEY`, `DEPLOY_HOST`, `DEPLOY_KNOWN_HOSTS` (pinned host key) — and the `SITE_URL` variable for the smoke test.

## Local commands

```bash
make serve   # live preview at http://localhost:1313
make check   # build, CV PDF and link check, same as CI
make deploy  # the same rsync as CI, from this machine
```

Needs Hugo extended 0.168+, Python 3 and Google Chrome.

## Layout

```
data/cv.yaml              CV content
content/                  pages and blog posts (Markdown)
layouts/                  templates
assets/css/               styles: site, CV and syntax highlighting
scripts/build-cv-pdf.sh   CV page -> PDF, page-count check
scripts/check_links.py    internal link checker
deploy/                   one-time server setup and the nginx site config
.github/workflows/        build and deploy pipeline
```
