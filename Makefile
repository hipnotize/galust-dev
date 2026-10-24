HUGO ?= hugo
PUBLIC ?= public

DEPLOY_HOST ?=
DEPLOY_KEY ?= $(HOME)/.ssh/site_deploy_ed25519

.PHONY: serve build pdf check deploy clean

serve:            ## live preview with drafts
	$(HUGO) server -D

build:            ## production build into ./public
	$(HUGO) --gc --minify -d $(PUBLIC)

pdf: build        ## build + CV PDF from the /cv/print/ page
	./scripts/build-cv-pdf.sh $(PUBLIC)

check: pdf        ## everything CI runs before deploy
	python3 scripts/check_links.py $(PUBLIC)

deploy: check     ## manual deploy from this machine, same rsync as CI: make deploy DEPLOY_HOST=...
	@test -n "$(DEPLOY_HOST)" || { echo "set DEPLOY_HOST" >&2; exit 1; }
	rsync -rlz --delete -e "ssh -i $(DEPLOY_KEY) -o IdentitiesOnly=yes" $(PUBLIC)/ site-deploy@$(DEPLOY_HOST):

clean:
	rm -rf $(PUBLIC) resources/_gen .hugo_build.lock
