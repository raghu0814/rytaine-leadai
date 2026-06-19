-- =====================================================================
-- supabase/tests/m0_3_schema.test.sql
-- M0-3 structural suite (pgTAP). Fixture-free schema-shape assertions.
-- Scope: schema correctness ONLY. Cross-tenant RLS behaviour is the
--        M0-6 isolation suite; RLS policies are M0-4. Not tested here.
-- Run:   pg_prove against a DB with 0001-0013 applied, or wrap in a txn:
--        begin; create extension if not exists pgtap; ... rollback;
-- =====================================================================
begin;
create extension if not exists pgtap;

select plan(48);

-- ---- 16 tables present ------------------------------------------------
select has_table('public','companies',       'companies exists');
select has_table('public','users',           'users exists');
select has_table('public','prompts',         'prompts exists');
select has_table('public','knowledge_bases', 'knowledge_bases exists');
select has_table('public','agent_configs',   'agent_configs exists');
select has_table('public','leads',           'leads exists');
select has_table('public','lead_notes',      'lead_notes exists');
select has_table('public','call_schedules',  'call_schedules exists');
select has_table('public','calls',           'calls exists');
select has_table('public','transcripts',     'transcripts exists');
select has_table('public','recordings',      'recordings exists');
select has_table('public','messages',        'messages exists');
select has_table('public','documents',       'documents exists');
select has_table('public','document_chunks', 'document_chunks exists');
select has_table('public','usage_logs',      'usage_logs exists');
select has_table('public','audit_logs',      'audit_logs exists');

-- ---- exactly 16 base tables, no more ----------------------------------
select is(
  (select count(*)::int from information_schema.tables
     where table_schema='public' and table_type='BASE TABLE'),
  16, 'exactly 16 public base tables');

-- ---- representative enums + exact labels ------------------------------
select has_enum('public','lead_status', 'lead_status enum exists');
select enum_has_labels('public','lead_status',
  ARRAY['new','contacted','qualified','unqualified',
        'callback_scheduled','unreachable','converted','lost'],
  'lead_status labels exact');
select enum_has_labels('public','lead_source',
  ARRAY['meta','google','manual','api'], 'lead_source labels exact');
select enum_has_labels('public','call_status',
  ARRAY['queued','initiated','ringing','in_progress','completed',
        'no_answer','busy','failed','voicemail','cancelled'],
  'call_status labels exact');
select is(
  (select count(*)::int from pg_type t join pg_namespace n on n.oid=t.typnamespace
     where t.typtype='e' and n.nspname='public'),
  26, 'exactly 26 enum types');

-- ---- leads: dedup columns + types + nullability -----------------------
select has_column('public','leads','is_potential_duplicate', 'leads.is_potential_duplicate');
select col_type_is('public','leads','is_potential_duplicate','boolean', 'flag is boolean');
select col_not_null('public','leads','is_potential_duplicate', 'flag NOT NULL');
select col_has_default('public','leads','is_potential_duplicate', 'flag defaults');
select has_column('public','leads','duplicate_of_lead_id', 'leads.duplicate_of_lead_id');
select col_type_is('public','leads','duplicate_of_lead_id','uuid', 'dup ptr is uuid');
select col_is_null('public','leads','duplicate_of_lead_id', 'dup ptr nullable');

-- ---- hard-dedup unique + self FK --------------------------------------
select col_is_unique('public','leads', ARRAY['company_id','source','external_lead_id'],
  'hard-dedup unique (company_id, source, external_lead_id)');
select fk_ok('public','leads','duplicate_of_lead_id','public','leads','id',
  'duplicate_of_lead_id self-FK to leads(id)');

-- ---- representative cross-table FKs -----------------------------------
select fk_ok('public','users','company_id','public','companies','id', 'users -> companies');
select fk_ok('public','leads','company_id','public','companies','id', 'leads -> companies');
select fk_ok('public','lead_notes','lead_id','public','leads','id', 'lead_notes -> leads');
select fk_ok('public','calls','lead_id','public','leads','id', 'calls -> leads');
select fk_ok('public','calls','call_schedule_id','public','call_schedules','id', 'calls -> call_schedules');
select fk_ok('public','call_schedules','call_id','public','calls','id', 'call_schedules -> calls (deferred FK)');
select fk_ok('public','document_chunks','document_id','public','documents','id', 'chunks -> documents');
select fk_ok('public','document_chunks','knowledge_base_id','public','knowledge_bases','id', 'chunks -> KB (denormalized)');

-- ---- transcripts 1:1 with calls ---------------------------------------
select col_is_unique('public','transcripts', ARRAY['call_id'], 'transcripts.call_id unique (1:1)');

-- ---- vector column + HNSW index ---------------------------------------
select has_column('public','document_chunks','embedding', 'embedding column present');
select has_index('public','document_chunks','idx_chunks_embedding', 'HNSW index present');

-- ---- triggers ---------------------------------------------------------
select has_trigger('public','leads','trg_leads_flag_duplicate', 'soft-dedup trigger on leads');
select has_trigger('public','leads','trg_leads_updated', 'updated_at trigger on leads');
select has_trigger('public','companies','trg_companies_updated', 'updated_at trigger on companies');
select is(
  (select count(*)::int from pg_trigger
     where not tgisinternal and tgfoid='public.set_updated_at'::regproc),
  10, 'exactly 10 set_updated_at triggers');

-- ---- functions exist --------------------------------------------------
select has_function('public','set_updated_at', 'set_updated_at() exists');
select has_function('public','flag_potential_duplicate_lead', 'flag_potential_duplicate_lead() exists');

select * from finish();
rollback;
