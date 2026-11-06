-- Members can add a place Apple Maps doesn't have. Added apart from its first use, as enum values require.
alter type public.place_provider add value if not exists 'custom';
