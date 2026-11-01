-- Friend requests get their own notification types. Added apart from their first use because a new
-- enum value cannot be used in the transaction that adds it.
alter type public.notification_type add value if not exists 'friend_request';
alter type public.notification_type add value if not exists 'friend_accept';
