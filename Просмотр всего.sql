--AUTOPARTS_OWNER
SELECT username FROM all_users ORDER BY username; --Просмотреть всех пользователей
SELECT * FROM user_role_privs; --Просмотреть всех привилегий пользователя
SHOW USER;
SHOW CON_NAME;
SELECT table_name FROM all_tables WHERE owner = 'AUTOPARTS_OWNER'; -- Посмотреть все таблицы принадлежащие AUTOPARTS_OWNER
SELECT role FROM dba_roles; --SYS: Просмотр ролей 
SELECT * FROM role_tab_privs WHERE role = 'ADMIN_ROLE';
SELECT * FROM role_tab_privs WHERE role = 'MANAGER_ROLE';

SELECT owner, object_name, object_type FROM all_objects -- Посмотреть кому принадлежит пакет AUTOPARTS_API
WHERE object_name = 'AUTOPARTS_API' AND object_type IN ('PACKAGE', 'PACKAGE BODY')
ORDER BY object_type;

--SYS
SELECT owner, view_name FROM dba_views WHERE owner = 'AUTOPARTS_OWNER' -- Посмотреть представления принадлежащие AUTOPARTS_OWNER
ORDER BY view_name;