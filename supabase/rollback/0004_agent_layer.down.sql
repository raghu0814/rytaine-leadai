-- DOWN for 0004_agent_layer. Local/staging only; prod uses PITR.
drop table if exists agent_configs cascade;
drop table if exists knowledge_bases cascade;
drop table if exists prompts cascade;
