# AGENTS.md

## Repository Purpose
This repository is the AI agent development environment.

## Agents

AI agents are not fixed.

Possible agents include:

- Codex
- Claude Code
- Other AI agents

The executor agent may change depending on the task.

Examples:

Codex  
- repository analysis  
- large codebase reasoning  
- architecture exploration  

Claude Code  
- CLI execution  
- script generation  
- debugging  
- CI investigation  

## Roles

Human  
- approval decisions
- merge pull requests
- GUI operations that cannot be automated

ChatGPT  
- architecture advisor
- design reviewer
- debugging auditor

AI Agents  
- implementation
- repository inspection
- automation tasks

## Source of Truth

GitHub repository is the single source of truth.

Local environments and external tools are working copies only.

## Workflow

Typical workflow:

1. Human defines task
2. AI agent analyzes repository
3. AI agent performs implementation
4. Changes are committed to GitHub
5. Human reviews and merges

## Rules

- Never commit secrets
- Always commit small logical changes
- Document major decisions in ADR
