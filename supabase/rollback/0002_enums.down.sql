-- DOWN for 0002_enums. Local/staging only; prod uses PITR.
-- Safe only after all consuming tables (0003-0011) are dropped.
drop type if exists usage_unit;
drop type if exists usage_service;
drop type if exists document_status;
drop type if exists document_source;
drop type if exists kb_status;
drop type if exists message_status;
drop type if exists message_provider;
drop type if exists message_direction;
drop type if exists message_channel;
drop type if exists schedule_status;
drop type if exists schedule_reason;
drop type if exists call_sentiment;
drop type if exists call_status;
drop type if exists call_direction;
drop type if exists llm_provider;
drop type if exists tts_provider;
drop type if exists stt_provider;
drop type if exists telephony_provider;
drop type if exists purchase_timeline;
drop type if exists lead_purpose;
drop type if exists lead_category;
drop type if exists lead_status;
drop type if exists lead_source;
drop type if exists user_status;
drop type if exists user_role;
drop type if exists company_status;
