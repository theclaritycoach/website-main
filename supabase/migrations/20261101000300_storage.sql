-- Private storage for resumes, work samples, and capability statements.
-- Files are uploaded by the server and opened by admins through short-lived
-- signed URLs. Nobody else can read them.
-- (Guarded so the schema can also be tested on plain Postgres without Supabase Storage.)

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values (
      'talent-files', 'talent-files', false, 5242880,
      array[
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'image/png',
        'image/jpeg'
      ]
    )
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;

    execute $p$
      create policy "talent files: admins read"
      on storage.objects for select to authenticated
      using (bucket_id = 'talent-files' and public.is_admin())
    $p$;

    execute $p$
      create policy "talent files: admins delete"
      on storage.objects for delete to authenticated
      using (bucket_id = 'talent-files' and public.is_admin())
    $p$;
  end if;
end $$;
