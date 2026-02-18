CREATE OR REPLACE PACKAGE AUTOPARTS_UTIL AS
    FUNCTION HASH_PASS(p_password IN VARCHAR2) RETURN VARCHAR2;
    PROCEDURE LOG_ACTIVITY(p_action IN VARCHAR2, p_details IN VARCHAR2);
    PROCEDURE RAISE_ERR(p_code IN NUMBER, p_msg IN VARCHAR2);
    
    -- Проверка прав доступа. p_level: 'USER', 'MANAGER', 'ADMIN'
    PROCEDURE CHECK_ACCESS(p_level IN VARCHAR2);
END AUTOPARTS_UTIL;
/

CREATE OR REPLACE PACKAGE BODY AUTOPARTS_UTIL AS

    FUNCTION HASH_PASS(p_password IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN RAWTOHEX(DBMS_CRYPTO.HASH(UTL_I18N.STRING_TO_RAW(p_password, 'AL32UTF8'), 4));
    END;

    PROCEDURE LOG_ACTIVITY(p_action IN VARCHAR2, p_details IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO ACTIVITY_LOGS (USERNAME, ACTION, DETAILS)
        VALUES (USER, p_action, SUBSTR(p_details, 1, 4000));
        COMMIT;
    END;

    PROCEDURE RAISE_ERR(p_code IN NUMBER, p_msg IN VARCHAR2) IS
    BEGIN
        LOG_ACTIVITY('ERROR', p_msg);
        RAISE_APPLICATION_ERROR(p_code, p_msg);
    END;

    PROCEDURE CHECK_ACCESS(p_level IN VARCHAR2) IS
        v_has_access BOOLEAN := FALSE;
    BEGIN
        -- Логика иерархии: 
        -- ADMIN имеет доступ ко всему.
        -- MANAGER имеет доступ к MANAGER и USER.
        -- USER имеет доступ только к USER.
        
        IF DBMS_SESSION.IS_ROLE_ENABLED('ADMIN_ROLE') THEN
            v_has_access := TRUE; -- Админ может всё
        ELSIF DBMS_SESSION.IS_ROLE_ENABLED('MANAGER_ROLE') THEN
            IF p_level IN ('MANAGER', 'USER') THEN
                v_has_access := TRUE;
            END IF;
        ELSIF DBMS_SESSION.IS_ROLE_ENABLED('USER_ROLE') THEN
            IF p_level = 'USER' THEN
                v_has_access := TRUE;
            END IF;
        END IF;

        IF NOT v_has_access THEN
            RAISE_ERR(-20000, 'Доступ запрещен. Недостаточно прав для выполнения операции уровня ' || p_level);
        END IF;
    END;

END AUTOPARTS_UTIL;
/