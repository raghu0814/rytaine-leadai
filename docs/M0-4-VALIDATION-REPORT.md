# M0-4 Validation Report

**Environment:** PostgreSQL 16.14 · pgvector 0.6.0 · pgTAP 1.3.2 (fresh instance)
**Schema basis:** M0-3 migrations 0001–0013 (reconstructed; live-equivalent)
**Date of run:** 2026-06-20 12:13 UTC

## Lifecycle results

| Phase | Result |
|---|---|
| Apply 0014 → 0015 → 0016 on fresh schema | clean, no errors |
| verify_m0_4.sql | PASS |
| m0_4_rls.test.sql (pgTAP) | 24 passed / 0 failed |
| Rollback 0016 → 0015 → 0014 | restores helpers=0, forced=0, policies=0 |
| Re-apply + re-verify + re-test | PASS · 24/24 |

## Confirmed table inventory (16, all RLS+FORCE)

agent_configs, audit_logs, call_schedules, calls, companies, document_chunks,
documents, knowledge_bases, lead_notes, leads, messages, prompts, recordings,
transcripts, usage_logs, users

`companies` keys on `id = current_company_id()`; the other 15 on `company_id = current_company_id()`.

## verify_m0_4.sql output

```
================ M0-4 VERIFICATION ================
--- helper functions ---
      proname       | volatility 
--------------------+------------
 current_company_id | STABLE
 current_user_role  | STABLE
(2 rows)

--- RLS / FORCE per public table ---
   table_name    | rls_enabled | rls_forced 
-----------------+-------------+------------
 agent_configs   | t           | t
 audit_logs      | t           | t
 call_schedules  | t           | t
 calls           | t           | t
 companies       | t           | t
 document_chunks | t           | t
 documents       | t           | t
 knowledge_bases | t           | t
 lead_notes      | t           | t
 leads           | t           | t
 messages        | t           | t
 prompts         | t           | t
 recordings      | t           | t
 transcripts     | t           | t
 usage_logs      | t           | t
 users           | t           | t
(16 rows)

--- policies per public table ---
    tablename    | policies 
-----------------+----------
 agent_configs   |        4
 audit_logs      |        1
 call_schedules  |        4
 calls           |        1
 companies       |        2
 document_chunks |        1
 documents       |        4
 knowledge_bases |        4
 lead_notes      |        4
 leads           |        4
 messages        |        2
 prompts         |        4
 recordings      |        1
 transcripts     |        1
 usage_logs      |        1
 users           |        4
(16 rows)

--- storage buckets ---
     id     | public 
------------+--------
 documents  | f
 recordings | f
(2 rows)

--- storage.objects policies ---
        policyname        |  cmd   
--------------------------+--------
 documents_admin_delete   | DELETE
 documents_admin_insert   | INSERT
 documents_admin_update   | UPDATE
 documents_tenant_select  | SELECT
 recordings_tenant_select | SELECT
(5 rows)

psql:verification/verify_m0_4.sql:94: NOTICE:  PASS: M0-4 verification — 2 helpers, all public tables RLS+FORCE+policied, 2 private buckets, 5 storage policies.
================ END VERIFICATION ================
```

## pgTAP output

```
1..24
ok 1 - helper current_company_id() exists
ok 2 - helper current_user_role() exists
ok 3 - public schema has the 16 M0-3 tables
ok 4 - all 16 public tables have RLS + FORCE
ok 5 - documents + recordings buckets exist and are private
ok 6 - Tenant A sees only its own 2 leads
ok 7 - Tenant A sees only its own company row
ok 8 - Tenant B sees only its own 3 leads
ok 9 - service_role bypasses RLS and sees all 5 leads
ok 10 - A manager can update its own 2 leads
ok 11 - A manager cross-tenant UPDATE of B leads affects 0 rows
ok 12 - A manager cross-tenant DELETE of B leads affects 0 rows
ok 13 - A manager can INSERT a lead in its own tenant
ok 14 - A viewer is denied INSERT on leads (manager+ required)
ok 15 - A manager cross-tenant INSERT (company_id=B) raises 42501
ok 16 - A admin can read its own usage_logs
ok 17 - A non-admin cannot read usage_logs (admin-only)
ok 18 - usage_logs UPDATE blocked (append-only, no client update policy)
ok 19 - usage_logs DELETE blocked (append-only)
ok 20 - A sees only its own 2 document_chunks (RAG tenant floor)
ok 21 - B sees only its own 1 document_chunk
ok 22 - A sees only its own documents object (folder = company_id)
ok 23 - A sees only its own recordings object
ok 24 - service_role sees all documents objects (bypass)
```
