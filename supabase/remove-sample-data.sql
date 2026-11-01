-- Removes every sample (fake) record. Run before launch: npm run sample:remove
begin;
delete from public.people where is_sample;
delete from public.firms where is_sample;
delete from public.projects where is_sample;
commit;
