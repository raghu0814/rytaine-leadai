-- =====================================================================
-- supabase/seed.sql
-- Milestone : M0-5 (Dev Seed)
-- Concern   : Deterministic, idempotent DEVELOPMENT data for one demo
--             tenant. NEVER promoted to a numbered migration; NEVER run
--             against production. Loaded by `supabase db reset` and by the
--             `make db-seed` target.
--
-- PURE SQL ONLY: no psql meta-commands (no backslash \set / \echo), and no
-- colon-prefixed psql variable references. All identifiers are literal UUIDs.
--   `supabase db reset` streams this file directly to Postgres, which does
--   not run the psql client preprocessor. All identifiers are literal UUIDs.
--
-- Design (locked project rules honoured):
--   * Seed data != migrations. This file lives outside supabase/migrations.
--   * Tenant isolation: every row carries the single demo company_id
--     11111111-1111-1111-1111-111111111111.
--   * Identity claims live in auth.users.raw_app_meta_data (app_metadata),
--     mirroring the JWT contract that current_company_id()/current_user_role()
--     read — user_metadata is never trusted for identity.
--   * Fixed UUIDs everywhere => re-runnable with identical results.
--   * Runs as the migration/superuser role (session pooler, port 5432),
--     which carries BYPASSRLS, so FORCE'd RLS does not block the load.
--
-- Fixed dev identifiers:
--   company        11111111-1111-1111-1111-111111111111
--   admin          a0000000-0000-0000-0000-000000000001
--   manager        a0000000-0000-0000-0000-000000000002
--   agent          a0000000-0000-0000-0000-000000000003
--   prompt         c0000000-0000-0000-0000-000000000001
--   knowledge_base d0000000-0000-0000-0000-000000000001
--   agent_config   e0000000-0000-0000-0000-000000000001
--   leads          f0000000-0000-0000-0000-00000000000{1..6}
--   document       f1000000-0000-0000-0000-000000000001
--   chunks         f2000000-0000-0000-0000-00000000000{1..3}
--   call_schedule  f3000000-0000-0000-0000-000000000001
--   call           f4000000-0000-0000-0000-000000000001
--
-- Re-run model: delete the demo company (cascades all public child rows),
--   delete its auth.users, then re-insert. Running this file N times leaves
--   the database in the same state as running it once.
-- =====================================================================

-- ---- Production guard (opt-in; ops sets app.environment=production) ----
do $$
begin
  if coalesce(current_setting('app.environment', true), '') = 'production' then
    raise exception 'Refusing to run dev seed: app.environment=production';
  end if;
end $$;

begin;

-- =====================================================================
-- 0. Reset (idempotency). Order matters: audit_logs.company_id is
--    ON DELETE SET NULL, so purge it explicitly; everything else cascades
--    from companies. Then remove the demo auth.users rows.
-- =====================================================================
delete from audit_logs where company_id = '11111111-1111-1111-1111-111111111111';
delete from companies   where id        = '11111111-1111-1111-1111-111111111111';
delete from auth.users  where id in (
  'a0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000002',
  'a0000000-0000-0000-0000-000000000003'
);

-- =====================================================================
-- 1. auth.users (Supabase-managed). Identity claims in raw_app_meta_data.
--    Password for all demo users: DevPass123!
-- =====================================================================
insert into auth.users
  (instance_id, id, aud, role, email, encrypted_password,
   email_confirmed_at, created_at, updated_at,
   raw_app_meta_data, raw_user_meta_data,
   confirmation_token, recovery_token, email_change_token_new, email_change,
   is_super_admin)
values
  ('00000000-0000-0000-0000-000000000000',
   'a0000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'admin@demo.rytaine.local', crypt('DevPass123!', gen_salt('bf')),
   now(), now(), now(),
   jsonb_build_object('provider','email','providers', array['email'],
                      'company_id','11111111-1111-1111-1111-111111111111','role','admin'),
   jsonb_build_object('full_name','Demo Admin'),
   '', '', '', '', false),
  ('00000000-0000-0000-0000-000000000000',
   'a0000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'manager@demo.rytaine.local', crypt('DevPass123!', gen_salt('bf')),
   now(), now(), now(),
   jsonb_build_object('provider','email','providers', array['email'],
                      'company_id','11111111-1111-1111-1111-111111111111','role','manager'),
   jsonb_build_object('full_name','Demo Manager'),
   '', '', '', '', false),
  ('00000000-0000-0000-0000-000000000000',
   'a0000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'agent@demo.rytaine.local', crypt('DevPass123!', gen_salt('bf')),
   now(), now(), now(),
   jsonb_build_object('provider','email','providers', array['email'],
                      'company_id','11111111-1111-1111-1111-111111111111','role','agent'),
   jsonb_build_object('full_name','Demo Agent'),
   '', '', '', '', false);

-- auth.identities so GoTrue email login resolves locally (best-effort shape).
insert into auth.identities
  (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values
  ('a0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
     jsonb_build_object('sub','a0000000-0000-0000-0000-000000000001','email','admin@demo.rytaine.local'),
     'email', now(), now(), now()),
  ('a0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000002',
     jsonb_build_object('sub','a0000000-0000-0000-0000-000000000002','email','manager@demo.rytaine.local'),
     'email', now(), now(), now()),
  ('a0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000003',
     jsonb_build_object('sub','a0000000-0000-0000-0000-000000000003','email','agent@demo.rytaine.local'),
     'email', now(), now(), now());

-- =====================================================================
-- 2. companies (tenant root)
-- =====================================================================
insert into companies (id, name, slug, status, plan, timezone, settings)
values ('11111111-1111-1111-1111-111111111111', 'RYtaine Demo Realty', 'demo-rytaine',
        'active', 'pro', 'Asia/Kolkata',
        jsonb_build_object('seed','m0-5','region','Hyderabad'));

-- =====================================================================
-- 3. users (app profiles, 1:1 with auth.users)
-- =====================================================================
insert into users (id, company_id, email, full_name, role, status, last_login_at)
values
  ('a0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'admin@demo.rytaine.local',   'Demo Admin',   'admin',   'active', now()),
  ('a0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'manager@demo.rytaine.local', 'Demo Manager', 'manager', 'active', now()),
  ('a0000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   'agent@demo.rytaine.local',   'Demo Agent',   'agent',   'active', null);

-- =====================================================================
-- 4. prompts (active Telugu script)
-- =====================================================================
insert into prompts
  (id, company_id, name, version, language, system_prompt, opening_line, variables, is_active, created_by)
values
  ('c0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'default-te', 1, 'te',
   'మీరు RYtaine అనే రియల్ ఎస్టేట్ AI అసిస్టెంట్. లీడ్‌తో మర్యాదగా, స్పష్టంగా తెలుగులో మాట్లాడండి. బడ్జెట్, స్థలం, కొనుగోలు సమయం గురించి అడగండి.',
   'నమస్కారం! నేను RYtaine నుండి మాట్లాడుతున్నాను. మీకు కొన్ని నిమిషాలు ఉన్నాయా?',
   jsonb_build_object('project','{{project_name}}'),
   true, 'a0000000-0000-0000-0000-000000000001');

-- =====================================================================
-- 5. knowledge_bases (one default per company)
-- =====================================================================
insert into knowledge_bases (id, company_id, name, description, status, is_default, created_by)
values ('d0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
        'Demo Projects KB', 'Seed knowledge base: demo Hyderabad projects.',
        'active', true, 'a0000000-0000-0000-0000-000000000001');

-- =====================================================================
-- 6. agent_configs (active)
-- =====================================================================
insert into agent_configs
  (id, company_id, name, prompt_id, knowledge_base_id,
   llm_provider, llm_model, stt_provider, stt_model, tts_provider, voice_id,
   telephony_provider, max_attempts, retry_intervals, qualification_fields,
   scoring_rules, is_active)
values
  ('e0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'Default Outbound TE',
   'c0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001',
   'openai', 'gpt-4o', 'deepgram', 'nova-3', 'elevenlabs', 'demo-voice-te',
   'twilio', 3, '[0, 3600, 86400]'::jsonb,
   '["budget","timeline","purpose"]'::jsonb,
   jsonb_build_object('hot', 70, 'warm', 40),
   true);

-- =====================================================================
-- 7. leads
--    Distinct-phone batch first (none flagged), then ONE intentional
--    soft-duplicate (same company + phone within 30 days) to exercise the
--    0013 BEFORE INSERT trigger. is_potential_duplicate / duplicate_of are
--    left to the trigger — never set by hand.
-- =====================================================================
insert into leads
  (id, company_id, external_lead_id, name, phone, email, city, source, campaign_name,
   lead_status, lead_score, lead_category, purpose, budget_min, budget_max,
   location_preference, purchase_timeline, site_visit_required, assigned_user_id, raw_payload)
values
  ('f0000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'META-1001', 'Ravi Kumar',  '+919000000011', 'ravi@example.com',  'Hyderabad', 'meta',   'Q2-Gachibowli',
   'new', 0, null, 'own_use', 5000000, 7500000, 'Gachibowli', 'within_3m', false,
   'a0000000-0000-0000-0000-000000000003', jsonb_build_object('form_id','fb-form-1')),
  ('f0000000-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111',
   'GOO-2002', 'Sneha Reddy', '+919000000012', 'sneha@example.com', 'Hyderabad', 'google', 'Search-Kondapur',
   'contacted', 35, 'warm', 'investment', 8000000, 12000000, 'Kondapur', 'within_6m', false,
   'a0000000-0000-0000-0000-000000000002', jsonb_build_object('gclid','xyz')),
  ('f0000000-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111',
   null, 'Anil Varma', '+919000000013', null, 'Hyderabad', 'manual', null,
   'qualified', 72, 'hot', 'own_use', 9000000, 11000000, 'Hitech City', 'immediate', true,
   'a0000000-0000-0000-0000-000000000003', '{}'::jsonb),
  ('f0000000-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111',
   'API-3003', 'Priya Singh', '+919000000014', 'priya@example.com', 'Hyderabad', 'api', 'Partner-Feed',
   'callback_scheduled', 55, 'warm', 'rental', 3000000, 4500000, 'Madhapur', 'within_12m', false,
   null, jsonb_build_object('partner','acme')),
  ('f0000000-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111',
   null, 'Karthik Rao', '+919000000015', 'karthik@example.com', 'Hyderabad', 'manual', null,
   'qualified', 88, 'hot', 'own_use', 12000000, 18000000, 'Financial District', 'immediate', true,
   'a0000000-0000-0000-0000-000000000002', '{}'::jsonb);

-- Intentional soft-duplicate of lead 3 (same phone +919000000013).
-- Separate statement so the trigger reliably sees the earlier row.
insert into leads
  (id, company_id, external_lead_id, name, phone, source, lead_status, purpose, raw_payload)
values
  ('f0000000-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111',
   null, 'Anil V (re-entry)', '+919000000013', 'manual', 'new', 'own_use',
   jsonb_build_object('note','duplicate-demo'));

-- =====================================================================
-- 8. lead_notes
-- =====================================================================
insert into lead_notes (company_id, lead_id, user_id, note)
values
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000003',
   'a0000000-0000-0000-0000-000000000003', 'Site visit requested for weekend.'),
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000005',
   'a0000000-0000-0000-0000-000000000002', 'High intent — budget confirmed.');

-- =====================================================================
-- 9. call_schedules + calls (break circular FK with a follow-up UPDATE)
-- =====================================================================
-- A completed attempt (linked to a call below) ...
insert into call_schedules
  (id, company_id, lead_id, agent_config_id, scheduled_at, attempt_number, reason, status, created_by, notes)
values
  ('f3000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'f0000000-0000-0000-0000-000000000003', 'e0000000-0000-0000-0000-000000000001',
   now() - interval '1 hour', 1, 'initial', 'completed',
   'a0000000-0000-0000-0000-000000000002', 'first attempt');

-- ... and a future pending attempt for the hot lead (scheduler hot path).
insert into call_schedules
  (company_id, lead_id, agent_config_id, scheduled_at, attempt_number, reason, status, created_by)
values
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000005',
   'e0000000-0000-0000-0000-000000000001', now() + interval '2 hours', 1, 'initial', 'pending',
   'a0000000-0000-0000-0000-000000000002');

insert into calls
  (id, company_id, lead_id, call_schedule_id, agent_config_id, provider, call_sid,
   direction, attempt_number, call_status, started_at, ended_at, duration_seconds,
   sentiment, qualification_score, summary)
values
  ('f4000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'f0000000-0000-0000-0000-000000000003', 'f3000000-0000-0000-0000-000000000001',
   'e0000000-0000-0000-0000-000000000001', 'twilio', 'CA-DEMO-0001',
   'outbound', 1, 'completed', now() - interval '55 minutes', now() - interval '52 minutes', 180,
   'positive', 72, 'Lead qualified; site visit booked.');

update call_schedules
   set call_id = 'f4000000-0000-0000-0000-000000000001'
 where id = 'f3000000-0000-0000-0000-000000000001';

-- =====================================================================
-- 10. transcripts + recordings (service-written tables; seed writes directly)
-- =====================================================================
insert into transcripts (company_id, call_id, language, full_text, segments, provider)
values
  ('11111111-1111-1111-1111-111111111111', 'f4000000-0000-0000-0000-000000000001', 'te',
   'నమస్కారం... అవును, నాకు ఆసక్తి ఉంది. బడ్జెట్ ఒక కోటి వరకు.',
   jsonb_build_array(
     jsonb_build_object('speaker','agent','start_ms',0,'end_ms',2200,'text','నమస్కారం','confidence',0.95),
     jsonb_build_object('speaker','lead','start_ms',2300,'end_ms',5200,'text','అవును, ఆసక్తి ఉంది','confidence',0.91)
   ),
   'deepgram');

insert into recordings (company_id, call_id, storage_path, duration_seconds, format, size_bytes, channels, is_encrypted)
values
  ('11111111-1111-1111-1111-111111111111', 'f4000000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111/recordings/f4000000-0000-0000-0000-000000000001.mp3',
   180, 'mp3', 1440000, 1, true);

-- =====================================================================
-- 11. messages (WhatsApp follow-up)
-- =====================================================================
insert into messages
  (company_id, lead_id, call_id, channel, direction, provider, provider_message_id,
   template_name, body, status, status_updated_at)
values
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000003',
   'f4000000-0000-0000-0000-000000000001', 'whatsapp', 'outbound', 'meta_whatsapp', 'WAMID-DEMO-0001',
   'site_visit_confirmation', 'మీ సైట్ విజిట్ నిర్ధారించబడింది. ధన్యవాదాలు!', 'delivered', now());

-- =====================================================================
-- 12. documents + document_chunks (RAG). Embeddings are deterministic
--     PLACEHOLDER vectors (1536-d) generated in-SQL so HNSW retrieval is
--     testable in dev — they are NOT real text-embedding-3-small output.
-- =====================================================================
insert into documents
  (id, company_id, knowledge_base_id, title, source_type, file_type, size_bytes,
   status, chunk_count, metadata, created_by)
values
  ('f1000000-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111',
   'd0000000-0000-0000-0000-000000000001', 'Skyline Towers — Project Brief',
   'text', 'text/plain', 2048, 'ready', 3,
   jsonb_build_object('project','Skyline Towers','price_band','5-12 Cr'),
   'a0000000-0000-0000-0000-000000000001');

insert into document_chunks
  (id, company_id, document_id, knowledge_base_id, chunk_index, content, token_count, embedding, metadata)
select v.id,
       '11111111-1111-1111-1111-111111111111',
       'f1000000-0000-0000-0000-000000000001',
       'd0000000-0000-0000-0000-000000000001',
       v.idx, v.content, v.tok,
       (
         select ('[' || string_agg(
                   round((sin((g * v.k)::double precision) / 2 + 0.5)::numeric, 6)::text,
                   ',' order by g) || ']')::vector
         from generate_series(1, 1536) g
       ),
       v.meta
from (values
  ('f2000000-0000-0000-0000-000000000001'::uuid, 0,
   'Skyline Towers is a premium residential project in the Financial District with 2 and 3 BHK units.',
   28, 0.013::double precision, jsonb_build_object('section','overview')),
  ('f2000000-0000-0000-0000-000000000002'::uuid, 1,
   'Pricing starts at 5 crore for 2 BHK and 12 crore for premium 3 BHK with skyline views.',
   26, 0.027::double precision, jsonb_build_object('section','pricing')),
  ('f2000000-0000-0000-0000-000000000003'::uuid, 2,
   'Amenities include a clubhouse, infinity pool, and 24x7 security. Possession in 18 months.',
   24, 0.041::double precision, jsonb_build_object('section','amenities'))
) as v(id, idx, content, tok, k, meta);

-- =====================================================================
-- 13. usage_logs (cost attribution sample)
-- =====================================================================
insert into usage_logs
  (company_id, lead_id, call_id, service, operation, provider_reference, quantity, unit, unit_cost, cost, currency, occurred_at)
values
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000003',
   'f4000000-0000-0000-0000-000000000001', 'openai', 'embedding', 'req-emb-1',
   3072, 'tokens', 0.00000002, 0.0000614, 'USD', now() - interval '50 minutes'),
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000003',
   'f4000000-0000-0000-0000-000000000001', 'elevenlabs', 'tts', 'req-tts-1',
   1200, 'characters', 0.00003, 0.036, 'USD', now() - interval '53 minutes'),
  ('11111111-1111-1111-1111-111111111111', 'f0000000-0000-0000-0000-000000000003',
   'f4000000-0000-0000-0000-000000000001', 'twilio', 'call_minutes', 'CA-DEMO-0001',
   3, 'minutes', 0.007, 0.021, 'USD', now() - interval '52 minutes');

-- =====================================================================
-- 14. audit_logs (seed marker)
-- =====================================================================
insert into audit_logs (company_id, actor_user_id, action, entity_type, entity_id, metadata)
values
  ('11111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001',
   'seed.load', 'company', '11111111-1111-1111-1111-111111111111',
   jsonb_build_object('milestone','m0-5'));

commit;
