-- Read with: sqlite3 -readonly "$DB" < Scripts/inspect-tab-groups.sql
-- Only schema and group/window metadata; no page URLs or tab titles.
PRAGMA query_only = ON;
.headers on
.mode column
PRAGMA table_info(windows_profiles);
SELECT id, active_tab_group_id, active_profile_id, local_tab_group_id,
       private_tab_group_id, is_last_session, date_closed
FROM windows;
SELECT id, tab_group_id, window_id FROM windows_tab_groups;
SELECT id, tab_group_id, window_id FROM windows_unnamed_tab_groups;
SELECT id, parent, type, subtype, special_id, title, deleted, hidden
FROM bookmarks
WHERE id IN (
    SELECT active_tab_group_id FROM windows
    UNION SELECT active_profile_id FROM windows
    UNION SELECT local_tab_group_id FROM windows
    UNION SELECT tab_group_id FROM windows_tab_groups
    UNION SELECT tab_group_id FROM windows_unnamed_tab_groups
);
