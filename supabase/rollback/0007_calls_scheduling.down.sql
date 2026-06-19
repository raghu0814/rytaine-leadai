-- DOWN for 0007_calls_scheduling. Local/staging only; prod uses PITR.
-- CASCADE clears the circular call_schedules <-> calls FK automatically.
drop table if exists recordings cascade;
drop table if exists transcripts cascade;
drop table if exists calls cascade;
drop table if exists call_schedules cascade;
