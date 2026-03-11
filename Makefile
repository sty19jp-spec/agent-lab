backup:
	bash scripts/drive-sync-run.sh

watch:
	gh run watch

logs:
	gh run list -L 5

status:
	gh run list

.PHONY: codex-task
codex-task:
	@TASK="$(TASK)" bash scripts/codex-task.sh
