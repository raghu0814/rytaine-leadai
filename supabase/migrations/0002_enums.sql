-- =====================================================================
-- Migration : 0002_enums
-- Milestone : M0-3 (schema)
-- Concern   : Enum types (stable domains)
-- Depends on: 0001_extensions
-- Forward-only. Immutable once merged.
--
-- ALTER TYPE policy (for later milestones, NOT this migration):
--   * Add a value via `alter type ... add value` in its OWN dedicated
--     migration — in some PG versions it cannot share a transaction with
--     other DDL. Keep it isolated.
--   * Removing/renaming enum values is hard; for volatile domains prefer
--     `text + check` or a lookup table. Revisit if a domain starts churning.
-- =====================================================================

-- ---- Tenant / identity ------------------------------------------------
create type company_status     as enum ('active','suspended','trial');
create type user_role          as enum ('admin','manager','agent');
create type user_status        as enum ('active','invited','disabled');

-- ---- Leads ------------------------------------------------------------
create type lead_source        as enum ('meta','google','manual','api');
create type lead_status         as enum ('new','contacted','qualified','unqualified',
                                         'callback_scheduled','unreachable','converted','lost');
create type lead_category       as enum ('hot','warm','cold');
create type lead_purpose        as enum ('own_use','investment','rental','unknown');
create type purchase_timeline   as enum ('immediate','within_3m','within_6m','within_12m','exploring');

-- ---- Providers --------------------------------------------------------
create type telephony_provider  as enum ('twilio','exotel','plivo');
create type stt_provider        as enum ('deepgram','sarvam');
create type tts_provider        as enum ('elevenlabs','sarvam');
create type llm_provider        as enum ('openai','sarvam');

-- ---- Calls ------------------------------------------------------------
create type call_direction      as enum ('outbound','inbound');
create type call_status         as enum ('queued','initiated','ringing','in_progress',
                                         'completed','no_answer','busy','failed','voicemail','cancelled');
create type call_sentiment      as enum ('positive','neutral','negative');

-- ---- Scheduling -------------------------------------------------------
create type schedule_reason     as enum ('initial','retry_no_answer','retry_busy','retry_failed',
                                         'caller_requested','manual');
create type schedule_status     as enum ('pending','processing','completed','cancelled','failed','skipped');

-- ---- Messaging --------------------------------------------------------
create type message_channel     as enum ('whatsapp','sms','email');
create type message_direction   as enum ('outbound','inbound');
create type message_provider     as enum ('twilio','meta_whatsapp','gupshup','other');
create type message_status      as enum ('queued','sent','delivered','read','failed','received');

-- ---- Knowledge base / RAG --------------------------------------------
create type kb_status           as enum ('active','archived');
create type document_source     as enum ('upload','url','text');
create type document_status     as enum ('pending','processing','ready','failed');

-- ---- Usage / cost -----------------------------------------------------
create type usage_service       as enum ('openai','deepgram','elevenlabs','sarvam',
                                         'twilio','exotel','plivo','other');
create type usage_unit          as enum ('tokens','seconds','characters','minutes','messages','requests');
