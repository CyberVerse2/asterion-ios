.PHONY: test test-macos test-core-api test-anime test-movies test-football run-macos build-core-api

test: test-macos test-core-api test-anime test-movies test-football

test-macos:
	cd apps/macos && swift test

test-core-api:
	cd services/core-api && npm run build && npx tsx --test test/*.test.ts

test-anime:
	cd services/anime && python3 -m unittest

test-movies:
	cd services/movies && python3 -m unittest

test-football:
	cd services/football && python3 -m unittest

run-macos:
	apps/macos/script/build_and_run.sh --verify

build-core-api:
	docker build --tag asterion-core-api:local services/core-api
