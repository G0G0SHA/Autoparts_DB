CREATE OR REPLACE PACKAGE AUTOPARTS_API_ADMIN AS
    -- Управление пользователями
    PROCEDURE create_user(p_username IN VARCHAR2, p_password IN VARCHAR2, p_role IN VARCHAR2, 
                         p_first_name IN VARCHAR2, p_last_name IN VARCHAR2, p_email IN VARCHAR2, p_phone IN VARCHAR2);
    PROCEDURE set_user_role(p_user_id_str IN VARCHAR2, p_role IN VARCHAR2);
    PROCEDURE get_all_users;
    PROCEDURE block_user(p_user_id_str IN VARCHAR2);
    PROCEDURE unblock_user(p_user_id_str IN VARCHAR2);

    -- Управление товарами
    PROCEDURE add_product(p_name IN VARCHAR2, p_cat_id_str IN VARCHAR2, p_sup_id_str IN VARCHAR2, 
                         p_price_str IN VARCHAR2, p_qty_str IN VARCHAR2, p_desc IN VARCHAR2);
    PROCEDURE remove_product(p_product_id_str IN VARCHAR2);

        PROCEDURE update_product(p_product_id_str IN VARCHAR2, p_name IN VARCHAR2, p_price_str IN VARCHAR2, p_qty_str IN VARCHAR2, p_cat_id_str IN VARCHAR2 DEFAULT NULL,  
        p_sup_id_str IN VARCHAR2 DEFAULT NULL);   
    -- Управление поставщиками
    PROCEDURE get_all_vendors;
    PROCEDURE add_vendor(p_name IN VARCHAR2, p_phone IN VARCHAR2, p_email IN VARCHAR2);
    PROCEDURE remove_vendor(p_sup_id_str IN VARCHAR2);
    PROCEDURE update_vendor( p_sup_id_str IN VARCHAR2, p_name IN VARCHAR2 DEFAULT NULL, p_phone IN VARCHAR2 DEFAULT NULL, 
    p_email IN VARCHAR2 DEFAULT NULL);
    
    -- Управление категориями
    PROCEDURE add_category(p_name IN VARCHAR2);
    PROCEDURE update_category(p_cat_id_str IN VARCHAR2, p_name IN VARCHAR2);
    PROCEDURE wipe_category(p_cat_id_str IN VARCHAR2);
    
    -- Отчетность и инструменты
    PROCEDURE SALES_REPORT(p_start_str IN VARCHAR2, p_end_str IN VARCHAR2);
    PROCEDURE export_products_json(p_filename IN VARCHAR2);
    PROCEDURE import_products_json(p_filename IN VARCHAR2);
    
    PROCEDURE clear_products;
    PROCEDURE print_table_products;
    PROCEDURE total_print;
    PROCEDURE total_parts_by_category(p_cat_id_str IN VARCHAR2);
    
    PROCEDURE EXPORT_LOGS_JSON(p_filename IN VARCHAR2);
    PROCEDURE IMPORT_LOGS_JSON(p_filename IN VARCHAR2);
    PROCEDURE CLEAR_ACTIVITY_LOGS;
    
END AUTOPARTS_API_ADMIN;
/

CREATE OR REPLACE PACKAGE BODY AUTOPARTS_API_ADMIN AS

    ----------------------------------------------------------------------------
    -- ВНУТРЕННИЕ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (ВАЛИДАЦИЯ И КОНВЕРТАЦИЯ)
    ----------------------------------------------------------------------------
    
    FUNCTION to_num(p_val IN VARCHAR2, p_name IN VARCHAR2) RETURN NUMBER IS
    v_num NUMBER;
BEGIN
    IF p_val IS NULL THEN RETURN NULL; END IF;
    -- Заменяем запятую на точку и ЯВНО говорим Oracle, что точка — это разделитель
    v_num := TO_NUMBER(
                TRIM(REPLACE(p_val, ',', '.')), 
                '99999999.99', 
                'NLS_NUMERIC_CHARACTERS = ''.,'''
             );
    RETURN v_num;
EXCEPTION
    WHEN OTHERS THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20001, 'Значение "' || p_name || '" должно быть числом (получено: ' || p_val || ')');
END;

    FUNCTION to_date_safe(p_val IN VARCHAR2, p_name IN VARCHAR2) RETURN DATE IS
        v_date DATE;
    BEGIN
        IF p_val IS NULL THEN RETURN NULL; END IF;
        -- Пробуем основные форматы
        BEGIN
            v_date := TO_DATE(p_val, 'DD.MM.YYYY');
        EXCEPTION WHEN OTHERS THEN
            v_date := TO_DATE(p_val, 'YYYY-MM-DD');
        END;
        RETURN v_date;
    EXCEPTION
        WHEN OTHERS THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20002, 'Некорректная дата для "' || p_name || '". Используйте формат ДД.ММ.ГГГГ');
    END;

    PROCEDURE check_not_null(p_val IN VARCHAR2, p_name IN VARCHAR2) IS
    BEGIN
        IF TRIM(p_val) IS NULL THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20003, 'Поле "' || p_name || '" обязательно для заполнения.');
        END IF;
    END;

    ----------------------------------------------------------------------------
    -- УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ
    ----------------------------------------------------------------------------

    PROCEDURE create_user(
        p_username   IN VARCHAR2, 
        p_password   IN VARCHAR2, 
        p_role       IN VARCHAR2, 
        p_first_name IN VARCHAR2, 
        p_last_name  IN VARCHAR2, 
        p_email      IN VARCHAR2, 
        p_phone      IN VARCHAR2
    ) IS
        v_uid NUMBER;
        v_role_clean VARCHAR2(20) := LOWER(TRIM(p_role));
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        check_not_null(p_username, 'Логин');
        check_not_null(p_password, 'Пароль');
        check_not_null(p_email, 'Email');
        
        IF v_role_clean NOT IN ('admin', 'manager', 'user') THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20726, 'Недопустимая роль: ' || p_role);
        END IF;

        INSERT INTO USERS (USERNAME, PASSWORD_HASH, ROLE, FIRST_NAME, LAST_NAME, EMAIL, PHONE)
        VALUES (p_username, AUTOPARTS_UTIL.HASH_PASS(p_password), v_role_clean, p_first_name, p_last_name, p_email, p_phone)
        RETURNING USER_ID INTO v_uid;

        INSERT INTO SHOPPING_CARTS (USER_ID) VALUES (v_uid);
        
        COMMIT;
        AUTOPARTS_UTIL.LOG_ACTIVITY('create_user', 'Admin created user: ' || p_username || ' with role ' || v_role_clean);
        DBMS_OUTPUT.PUT_LINE('Пользователь ' || p_username || ' успешно создан (ID: ' || v_uid || ')');
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK; AUTOPARTS_UTIL.RAISE_ERR(-20719, 'Пользователь с таким логином или почтой уже существует.');
        WHEN OTHERS THEN ROLLBACK; RAISE;
    END;

    PROCEDURE set_user_role(p_user_id_str IN VARCHAR2, p_role IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
        v_role_clean VARCHAR2(20) := LOWER(TRIM(p_role));
        v_exists NUMBER;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        check_not_null(p_role, 'Роль');
        
        SELECT COUNT(*) INTO v_exists FROM USERS WHERE USER_ID = v_uid;
        IF v_exists = 0 THEN AUTOPARTS_UTIL.RAISE_ERR(-20725, 'Пользователь ID=' || v_uid || ' не найден.'); END IF;
        
        IF v_role_clean NOT IN ('admin', 'manager', 'user') THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20726, 'Недопустимая роль.');
        END IF;

        UPDATE USERS SET ROLE = v_role_clean WHERE USER_ID = v_uid;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Роль пользователя ID=' || v_uid || ' изменена на ' || v_role_clean);
    END;

    PROCEDURE get_all_users IS
    v_found_active BOOLEAN := FALSE;
    v_found_inactive BOOLEAN := FALSE;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
    
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 120, '-'));
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 6) || 
        RPAD('ЛОГИН', 20) || 
        RPAD('РОЛЬ', 12) || 
        RPAD('СТАТУС', 12) || 
        --RPAD('АКТИВНОСТЬ', 12) || 
        RPAD('EMAIL', 25) || 
        'ДАТА РЕГИСТРАЦИИ'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 120, '-'));
    
    -- Сначала активные пользователи
    DBMS_OUTPUT.PUT_LINE('АКТИВНЫЕ ПОЛЬЗОВАТЕЛИ:');
    FOR r IN (
        SELECT * FROM USERS 
        WHERE IS_ACTIVE = 'Y' 
        ORDER BY USER_ID
    ) LOOP
        v_found_active := TRUE;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.user_id, 6) || 
            RPAD(r.username, 20) || 
            RPAD(r.role, 12) || 
            RPAD(CASE WHEN r.is_blocked = 'Y' THEN 'БЛОК' ELSE 'НЕ БЛОК' END, 12) || 
            --RPAD('АКТИВЕН', 12) || 
            RPAD(r.email, 25) || 
            TO_CHAR(r.registered_date, 'DD.MM.YYYY')
        );
    END LOOP;
    
    IF NOT v_found_active THEN
        DBMS_OUTPUT.PUT_LINE('Активных пользователей нет.');
    END IF;
    
    -- Затем деактивированные пользователи
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'НЕАКТИВНЫЕ ПОЛЬЗОВАТЕЛИ:');
    FOR r IN (
        SELECT * FROM USERS 
        WHERE IS_ACTIVE = 'N' 
        ORDER BY USER_ID
    ) LOOP
        v_found_inactive := TRUE;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.user_id, 6) || 
            RPAD(r.username, 20) || 
            RPAD(r.role, 12) || 
            RPAD(CASE WHEN r.is_blocked = 'Y' THEN 'ЗАБЛОКИРОВАН' ELSE 'АКТИВЕН' END, 12) || 
            RPAD('НЕАКТИВЕН', 12) || 
            RPAD(r.email, 25) || 
            TO_CHAR(r.registered_date, 'DD.MM.YYYY')
        );
    END LOOP;
    
    IF NOT v_found_inactive THEN
        DBMS_OUTPUT.PUT_LINE('Неактивных пользователей нет.');
    END IF;
    
    -- Статистика
    DECLARE
        v_total_users NUMBER;
        v_active_users NUMBER;
        v_inactive_users NUMBER;
        v_blocked_users NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_total_users FROM USERS;
        SELECT COUNT(*) INTO v_active_users FROM USERS WHERE IS_ACTIVE = 'Y';
        SELECT COUNT(*) INTO v_inactive_users FROM USERS WHERE IS_ACTIVE = 'N';
        SELECT COUNT(*) INTO v_blocked_users FROM USERS WHERE IS_BLOCKED = 'Y';
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'СТАТИСТИКА ПОЛЬЗОВАТЕЛЕЙ:');
        DBMS_OUTPUT.PUT_LINE('Всего пользователей: ' || v_total_users);
        DBMS_OUTPUT.PUT_LINE('Активных: ' || v_active_users);
        DBMS_OUTPUT.PUT_LINE('Неактивных: ' || v_inactive_users);
        DBMS_OUTPUT.PUT_LINE('Заблокированных: ' || v_blocked_users);
    END;
END get_all_users;
    
    PROCEDURE block_user(p_user_id_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        UPDATE USERS SET IS_BLOCKED = 'Y' WHERE USER_ID = v_uid;
        IF SQL%ROWCOUNT = 0 THEN AUTOPARTS_UTIL.RAISE_ERR(-20725, 'Пользователь не найден.'); END IF;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Пользователь ID=' || v_uid || ' заблокирован.');
    END;

    PROCEDURE unblock_user(p_user_id_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        UPDATE USERS SET IS_BLOCKED = 'N' WHERE USER_ID = v_uid;
        IF SQL%ROWCOUNT = 0 THEN AUTOPARTS_UTIL.RAISE_ERR(-20725, 'Пользователь не найден.'); END IF;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Пользователь ID=' || v_uid || ' разблокирован.');
    END;

    ----------------------------------------------------------------------------
    -- УПРАВЛЕНИЕ ТОВАРАМИ
    ----------------------------------------------------------------------------
    
    PROCEDURE add_product(
        p_name IN VARCHAR2, p_cat_id_str IN VARCHAR2, p_sup_id_str IN VARCHAR2, 
        p_price_str IN VARCHAR2, p_qty_str IN VARCHAR2, p_desc IN VARCHAR2
    ) IS
        v_cid   NUMBER := to_num(p_cat_id_str, 'ID Категории');
        v_sid   NUMBER := to_num(p_sup_id_str, 'ID Поставщика');
        v_price NUMBER := to_num(p_price_str, 'Цена');
        v_qty   NUMBER := to_num(p_qty_str, 'Количество');
        v_cat_active CHAR(1);
        v_sup_active CHAR(1);
        v_cat_name VARCHAR2(100);
        v_sup_name VARCHAR2(100);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        check_not_null(p_name, 'Название товара');
        
        -- Проверка существования и активности категории
        BEGIN
            SELECT NAME, IS_ACTIVE INTO v_cat_name, v_cat_active 
            FROM CATEGORIES 
            WHERE CATEGORY_ID = v_cid;
            
            IF v_cat_active = 'N' THEN
                AUTOPARTS_UTIL.RAISE_ERR(-20751, 
                    'Категория "' || v_cat_name || '" (ID=' || v_cid || 
                    ') деактивирована. Сначала восстановите категорию или выберите другую.');
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20701, 'Категория ID=' || v_cid || ' не существует.'); 
        END;
    
        -- Проверка существования и активности поставщика
        BEGIN
            SELECT COMPANY_NAME, IS_ACTIVE INTO v_sup_name, v_sup_active 
            FROM SUPPLIERS 
            WHERE SUPPLIER_ID = v_sid;
            
            IF v_sup_active = 'N' THEN
                AUTOPARTS_UTIL.RAISE_ERR(-20752, 
                    'Поставщик "' || v_sup_name || '" (ID=' || v_sid || 
                    ') деактивирован. Сначала восстановите поставщика или выберите другого.');
            END IF;
        EXCEPTION WHEN NO_DATA_FOUND THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20702, 'Поставщик ID=' || v_sid || ' не существует.'); 
        END;
    
        -- Проверка цены
        IF v_price < 0 THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20005, 'Цена не может быть отрицательной.'); 
        END IF;
        
        -- Проверка количества
        IF v_qty < 0 THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20753, 'Количество не может быть отрицательным.');
        END IF;
    
        -- Вставка товара
        INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
        VALUES (p_name, v_cid, v_sid, v_price, NVL(v_qty, 0), p_desc);
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Товар "' || p_name || '" успешно добавлен.');
        DBMS_OUTPUT.PUT_LINE('Категория: ' || v_cat_name || ' (ID: ' || v_cid || ')');
        DBMS_OUTPUT.PUT_LINE('Поставщик: ' || v_sup_name || ' (ID: ' || v_sid || ')');
        DBMS_OUTPUT.PUT_LINE('Цена: ' || v_price || ', Количество: ' || NVL(v_qty, 0));
        
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            ROLLBACK;
            AUTOPARTS_UTIL.RAISE_ERR(-20754, 'Товар с таким названием уже существует: ' || p_name);
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END add_product;

    PROCEDURE remove_product(p_product_id_str IN VARCHAR2) IS
        v_id NUMBER := to_num(p_product_id_str, 'ID товара');
        v_product_name VARCHAR2(100);
        v_in_orders NUMBER;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Получаем название товара для сообщения
        SELECT NAME INTO v_product_name 
        FROM PRODUCTS 
        WHERE PRODUCT_ID = v_id;
        
        -- Проверяем, есть ли товар в заказах
        SELECT COUNT(*) INTO v_in_orders
        FROM ORDER_ITEMS
        WHERE PRODUCT_ID = v_id;
        
        -- SOFT DELETE с сохранением истории
        UPDATE PRODUCTS 
        SET IS_ACTIVE = 'N',
            QUANTITY_IN_STOCK = 0,
            NAME = NAME || ' [УДАЛЕНО ' || TO_CHAR(SYSDATE, 'DD.MM.YYYY') || ']'
        WHERE PRODUCT_ID = v_id;
        
        COMMIT;
        
        DBMS_OUTPUT.PUT_LINE('Товар "' || v_product_name || '" удалён.');
        
        
    END remove_product;
    
    PROCEDURE update_product(
        p_product_id_str IN VARCHAR2, 
        p_name IN VARCHAR2, 
        p_price_str IN VARCHAR2, 
        p_qty_str IN VARCHAR2,
        p_cat_id_str IN VARCHAR2 DEFAULT NULL,  -- Добавили опциональное изменение категории
        p_sup_id_str IN VARCHAR2 DEFAULT NULL   -- Добавили опциональное изменение поставщика
    ) IS
        v_pid   NUMBER := to_num(p_product_id_str, 'ID Товара');
        v_price NUMBER := to_num(p_price_str, 'Цена');
        v_qty   NUMBER := to_num(p_qty_str, 'Количество');
        v_cid   NUMBER;
        v_sid   NUMBER;
        v_cat_active CHAR(1);
        v_sup_active CHAR(1);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Если меняем категорию, проверяем её активность
        IF p_cat_id_str IS NOT NULL THEN
            v_cid := to_num(p_cat_id_str, 'Новая ID Категории');
            
            SELECT IS_ACTIVE INTO v_cat_active 
            FROM CATEGORIES 
            WHERE CATEGORY_ID = v_cid;
            
            IF v_cat_active = 'N' THEN
                AUTOPARTS_UTIL.RAISE_ERR(-20751, 
                    'Невозможно переместить товар в деактивированную категорию.');
            END IF;
        END IF;
        
        -- Если меняем поставщика, проверяем его активность
        IF p_sup_id_str IS NOT NULL THEN
            v_sid := to_num(p_sup_id_str, 'Новая ID Поставщика');
            
            SELECT IS_ACTIVE INTO v_sup_active 
            FROM SUPPLIERS 
            WHERE SUPPLIER_ID = v_sid;
            
            IF v_sup_active = 'N' THEN
                AUTOPARTS_UTIL.RAISE_ERR(-20752, 
                    'Невозможно изменить поставщика на деактивированного.');
            END IF;
        END IF;
        
        -- Обновление товара
        UPDATE PRODUCTS 
        SET NAME = NVL(p_name, NAME),
            PRICE = NVL(v_price, PRICE),
            QUANTITY_IN_STOCK = NVL(v_qty, QUANTITY_IN_STOCK),
            CATEGORY_ID = NVL(v_cid, CATEGORY_ID),
            SUPPLIER_ID = NVL(v_sid, SUPPLIER_ID)
        WHERE PRODUCT_ID = v_pid;
        
        IF SQL%ROWCOUNT = 0 THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20703, 'Товар не найден.'); 
        END IF;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Товар ID=' || v_pid || ' успешно обновлен.');
    END update_product;
    
    ----------------------------------------------------------------------------
    -- УПРАВЛЕНИЕ ПОСТАВЩИКАМИ И КАТЕГОРИЯМИ
    ----------------------------------------------------------------------------
    PROCEDURE get_all_vendors IS
        v_found_active BOOLEAN := FALSE;
        v_found_inactive BOOLEAN := FALSE;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Активные поставщики
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'АКТИВНЫЕ ПОСТАВЩИКИ:');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('ID', 5) || 
            RPAD('НАЗВАНИЕ КОМПАНИИ', 30) || 
            RPAD('ТЕЛЕФОН', 20) || 
            RPAD('EMAIL', 25) || 
            'СТАТУС'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
        
        FOR r IN (SELECT * FROM SUPPLIERS WHERE IS_ACTIVE = 'Y' ORDER BY SUPPLIER_ID) LOOP
            v_found_active := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.supplier_id, 5) || 
                RPAD(r.company_name, 30) || 
                RPAD(NVL(r.phone, '-'), 20) || 
                RPAD(NVL(r.email, '-'), 25) || 
                'АКТИВЕН'
            );
        END LOOP;
        
        IF NOT v_found_active THEN
            DBMS_OUTPUT.PUT_LINE('Активных поставщиков нет.');
        END IF;
        
        -- Деактивированные поставщики
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'НЕАКТИВНЫЕ ПОСТАВЩИКИ:');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));
        
        FOR r IN (SELECT * FROM SUPPLIERS WHERE IS_ACTIVE = 'N' ORDER BY SUPPLIER_ID) LOOP
            v_found_inactive := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.supplier_id, 5) || 
                RPAD(r.company_name, 30) || 
                RPAD(NVL(r.phone, '-'), 20) || 
                RPAD(NVL(r.email, '-'), 25) || 
                'НЕАКТИВЕН'
            );
        END LOOP;
        
        IF NOT v_found_inactive THEN
            DBMS_OUTPUT.PUT_LINE('Неактивных поставщиков нет.');
        END IF;
        
        -- Статистика
        DECLARE
            v_total NUMBER;
            v_active NUMBER;
            v_inactive NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_total FROM SUPPLIERS;
            SELECT COUNT(*) INTO v_active FROM SUPPLIERS WHERE IS_ACTIVE = 'Y';
            SELECT COUNT(*) INTO v_inactive FROM SUPPLIERS WHERE IS_ACTIVE = 'N';
            
            DBMS_OUTPUT.PUT_LINE(CHR(10) || 'СТАТИСТИКА:');
            DBMS_OUTPUT.PUT_LINE('Всего поставщиков: ' || v_total);
            DBMS_OUTPUT.PUT_LINE('Активных: ' || v_active);
            DBMS_OUTPUT.PUT_LINE('Неактивных: ' || v_inactive);
        END;
    END get_all_vendors;
    
    PROCEDURE add_vendor(p_name IN VARCHAR2, p_phone IN VARCHAR2, p_email IN VARCHAR2) IS
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        check_not_null(p_name, 'Название компании');
        INSERT INTO SUPPLIERS (COMPANY_NAME, PHONE, EMAIL) VALUES (p_name, p_phone, p_email);
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Поставщик добавлен.');
    END;

    PROCEDURE remove_vendor(p_sup_id_str IN VARCHAR2) IS
        v_sid NUMBER := to_num(p_sup_id_str, 'ID Поставщика');
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        DELETE FROM SUPPLIERS WHERE SUPPLIER_ID = v_sid;
        IF SQL%ROWCOUNT = 0 THEN AUTOPARTS_UTIL.RAISE_ERR(-20702, 'Поставщик не найден.'); END IF;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Поставщик удален.');
    END;

    PROCEDURE update_vendor(
    p_sup_id_str IN VARCHAR2, 
    p_name       IN VARCHAR2 DEFAULT NULL, 
    p_phone      IN VARCHAR2 DEFAULT NULL, 
    p_email      IN VARCHAR2 DEFAULT NULL
) IS
    v_sid NUMBER := to_num(p_sup_id_str, 'ID Поставщика');
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');

    UPDATE SUPPLIERS 
    SET COMPANY_NAME = NVL(p_name, COMPANY_NAME),
        PHONE        = NVL(p_phone, PHONE),
        EMAIL        = NVL(p_email, EMAIL)
    WHERE SUPPLIER_ID = v_sid;

    IF SQL%ROWCOUNT = 0 THEN 
        AUTOPARTS_UTIL.RAISE_ERR(-20702, 'Поставщик с ID ' || v_sid || ' не найден.'); 
    END IF;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Данные поставщика ID ' || v_sid || ' успешно обновлены.');
END update_vendor;

    PROCEDURE add_category(p_name IN VARCHAR2) IS
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        check_not_null(p_name, 'Имя категории');
        INSERT INTO CATEGORIES (NAME) VALUES (p_name);
        COMMIT;
    END;

    PROCEDURE update_category(p_cat_id_str IN VARCHAR2, p_name IN VARCHAR2) IS
        v_cid NUMBER := to_num(p_cat_id_str, 'ID Категории');
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        UPDATE CATEGORIES SET NAME = p_name WHERE CATEGORY_ID = v_cid;
        IF SQL%ROWCOUNT = 0 THEN AUTOPARTS_UTIL.RAISE_ERR(-20701, 'Категория не найдена.'); END IF;
        COMMIT;
    END;

    PROCEDURE wipe_category(p_cat_id_str IN VARCHAR2) IS
        v_cid NUMBER := to_num(p_cat_id_str, 'ID Категории');
        v_cat_name VARCHAR2(100);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Проверяем существование категории
        BEGIN
            SELECT NAME INTO v_cat_name 
            FROM CATEGORIES 
            WHERE CATEGORY_ID = v_cid;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20701, 'Категория не найдена.');
        END;
        
        -- SOFT DELETE: Деактивируем категорию
        UPDATE CATEGORIES 
        SET IS_ACTIVE = 'N',
            NAME = NAME || ' [УДАЛЕНО ' || TO_CHAR(SYSDATE, 'DD.MM.YYYY') || ']'
        WHERE CATEGORY_ID = v_cid;
        
        -- SOFT DELETE: Деактивируем все товары в этой категории
        UPDATE PRODUCTS 
        SET IS_ACTIVE = 'N'
        WHERE CATEGORY_ID = v_cid;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Категория "' || v_cat_name || 'удалена');
    END wipe_category;

    ----------------------------------------------------------------------------
    -- ОТЧЕТНОСТЬ И АНАЛИТИКА
    ----------------------------------------------------------------------------

   PROCEDURE SALES_REPORT(p_start_str IN VARCHAR2, p_end_str IN VARCHAR2) IS
        v_start DATE;
        v_end   DATE;
        v_total_period NUMBER(10,2) := 0;
        v_count NUMBER := 0;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Конвертация строк в даты (используем формат из вашего вызова)
        BEGIN
            v_start := TO_DATE(p_start_str, 'DD.MM.YYYY');
            v_end   := TO_DATE(p_end_str, 'DD.MM.YYYY');
        EXCEPTION WHEN OTHERS THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20002, 'Неверный формат даты. Используйте DD.MM.YYYY');
        END;
    
        -- 1. ПРОВЕРКА: Первая дата не должна быть больше второй
        IF v_start > v_end THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20003, 'Ошибка: Дата начала ('||p_start_str||') не может быть позже даты окончания ('||p_end_str||')');
        END IF;
    
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 60, '='));
        DBMS_OUTPUT.PUT_LINE('ОТЧЕТ ПО ПРОДАЖАМ С ' || p_start_str || ' ПО ' || p_end_str);
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 60, '='));
        DBMS_OUTPUT.PUT_LINE(RPAD('ID ЗАКАЗА', 15) || RPAD('ДАТА', 15) || 'СУММА');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    
        -- 2. ВЫВОД СУММ ПО ЗАКАЗАМ (без детализации товаров)
        FOR r IN (
            SELECT ORDER_ID, ORDER_DATE, TOTAL_AMOUNT 
            FROM ORDERS 
            WHERE ORDER_DATE BETWEEN v_start AND v_end + 0.99999 -- Включаем весь последний день
              AND STATUS = 'Completed'
            ORDER BY ORDER_DATE
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.ORDER_ID, 15) || 
                RPAD(TO_CHAR(r.ORDER_DATE, 'DD.MM.YYYY'), 15) || 
                TO_CHAR(r.TOTAL_AMOUNT, '999990.99')
            );
            v_total_period := v_total_period + r.TOTAL_AMOUNT;
            v_count := v_count + 1;
        END LOOP;
    
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
        DBMS_OUTPUT.PUT_LINE('ИТОГО ЗА ПЕРИОД: ' || TO_CHAR(v_total_period, '999,999,990.99'));
        DBMS_OUTPUT.PUT_LINE('ВСЕГО ЗАКАЗОВ:   ' || v_count);
        DBMS_OUTPUT.PUT_LINE(RPAD('=', 60, '='));
        
        AUTOPARTS_UTIL.LOG_ACTIVITY('report', 'Generated sales report for period: ' || p_start_str || '-' || p_end_str);
    END SALES_REPORT;

    -- Простая процедура анализа продукции
PROCEDURE total_print IS
    v_total_products NUMBER;
    v_in_stock NUMBER;
    v_out_of_stock NUMBER;
    v_total_quantity NUMBER;
    v_total_value NUMBER;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
    
    -- Общая статистика
    SELECT 
        COUNT(*) as total_products,
        SUM(CASE WHEN QUANTITY_IN_STOCK > 0 THEN 1 ELSE 0 END) as in_stock,
        SUM(CASE WHEN QUANTITY_IN_STOCK = 0 THEN 1 ELSE 0 END) as out_of_stock,
        SUM(QUANTITY_IN_STOCK) as total_quantity,
        SUM(QUANTITY_IN_STOCK * PRICE) as total_value
    INTO v_total_products, v_in_stock, v_out_of_stock, 
         v_total_quantity, v_total_value
    FROM PRODUCTS;
    
    -- Вывод результатов
    DBMS_OUTPUT.PUT_LINE(CHR(10) || '=== АНАЛИЗ ПРОДУКЦИИ ===');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 40, '-'));
    DBMS_OUTPUT.PUT_LINE('Общее количество товаров в базе: ' || v_total_products);
    DBMS_OUTPUT.PUT_LINE('Товаров в наличии: ' || NVL(v_in_stock, 0));
    DBMS_OUTPUT.PUT_LINE('Товаров не в наличии: ' || NVL(v_out_of_stock, 0));
    DBMS_OUTPUT.PUT_LINE('Общее количество на складе: ' || NVL(v_total_quantity, 0) || ' шт.');
    DBMS_OUTPUT.PUT_LINE('Общая стоимость всех товаров: ' || 
                        TO_CHAR(NVL(v_total_value, 0), '999G999G990D00') || ' руб.');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 40, '-'));
    
    -- Дополнительно: товары с самым большим остатком
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ТОП-5 товаров по количеству на складе:');
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    
    FOR r IN (
        SELECT p.NAME, p.QUANTITY_IN_STOCK, p.PRICE,
               (p.QUANTITY_IN_STOCK * p.PRICE) as ITEM_VALUE
        FROM PRODUCTS p
        WHERE p.QUANTITY_IN_STOCK > 0
        ORDER BY p.QUANTITY_IN_STOCK DESC
        FETCH FIRST 5 ROWS ONLY
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(SUBSTR(r.NAME, 1, 30), 32) || ' | ' ||
            RPAD(r.QUANTITY_IN_STOCK || ' шт.', 10) || ' | ' ||
            TO_CHAR(r.ITEM_VALUE, '999G990D00') || ' руб.'
        );
    END LOOP;
    
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    
END total_print;

    PROCEDURE total_parts_by_category(p_cat_id_str IN VARCHAR2) IS
        v_cid NUMBER := to_num(p_cat_id_str, 'ID Категории');
        v_count NUMBER;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        SELECT SUM(QUANTITY_IN_STOCK) INTO v_count FROM PRODUCTS WHERE CATEGORY_ID = v_cid;
        DBMS_OUTPUT.PUT_LINE('Всего единиц товара в категории ID=' || v_cid || ': ' || NVL(v_count, 0));
    END;

    ----------------------------------------------------------------------------
    -- СЛУЖЕБНЫЕ ИМПОРТ / ЭКСПОРТ (ЗАГЛУШКИ С ЛОГИКОЙ ТИПОВ)
    ----------------------------------------------------------------------------
    
    PROCEDURE export_products_json(p_filename IN VARCHAR2) IS
    f_handle    UTL_FILE.FILE_TYPE;
    v_json_clob CLOB;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
    
    -- Получаем данные из таблицы PRODUCTS, включая все поля
    SELECT JSON_ARRAYAGG(
               JSON_OBJECT(
                   'product_id'        VALUE PRODUCT_ID,
                   'name'              VALUE NAME,
                   'category_id'       VALUE CATEGORY_ID,
                   'supplier_id'       VALUE SUPPLIER_ID,
                   'price'             VALUE PRICE,
                   'quantity_in_stock' VALUE QUANTITY_IN_STOCK,
                   'is_active'         VALUE IS_ACTIVE,
                   'description'       VALUE DESCRIPTION
               ) RETURNING CLOB
           )
    INTO v_json_clob
    FROM PRODUCTS
    WHERE IS_ACTIVE = 'Y'; -- Экспортируем только активные товары
    
    f_handle := UTL_FILE.FOPEN('DATA_EXPORT_DIR', p_filename, 'W', 32767);
    
    -- Поскольку файл может быть большим, пишем по частям
    DECLARE
        v_offset NUMBER := 1;
        v_chunk  VARCHAR2(32767);
        v_buffer NUMBER := 32000;
    BEGIN
        LOOP
            EXIT WHEN v_offset > DBMS_LOB.GETLENGTH(v_json_clob);
            v_chunk := DBMS_LOB.SUBSTR(v_json_clob, v_buffer, v_offset);
            UTL_FILE.PUT(f_handle, v_chunk);
            v_offset := v_offset + v_buffer;
        END LOOP;
    END;
    
    UTL_FILE.FCLOSE(f_handle);

    AUTOPARTS_UTIL.LOG_ACTIVITY('export_json', 'Каталог товаров экспортирован в файл: '||p_filename);
    DBMS_OUTPUT.PUT_LINE('Экспорт завершен успешно.');

EXCEPTION
    WHEN OTHERS THEN
        IF UTL_FILE.IS_OPEN(f_handle) THEN UTL_FILE.FCLOSE(f_handle); END IF;
        AUTOPARTS_UTIL.RAISE_ERR(-20801, 'Ошибка экспорта: ' || SQLERRM);
END export_products_json;

PROCEDURE import_products_json(p_filename IN VARCHAR2) IS
    f_handle    UTL_FILE.FILE_TYPE;
    v_line      VARCHAR2(32767);
    v_json_clob CLOB;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN'); 
    
    BEGIN
        f_handle := UTL_FILE.FOPEN('DATA_EXPORT_DIR', p_filename, 'R', 32767);
        DBMS_LOB.CREATETEMPORARY(v_json_clob, TRUE);
        LOOP
            BEGIN
                UTL_FILE.GET_LINE(f_handle, v_line);
                -- Добавляем саму строку и символ переноса строки, чтобы JSON не "слипся"
                IF v_line IS NOT NULL THEN
                    DBMS_LOB.WRITEAPPEND(v_json_clob, LENGTH(v_line), v_line);
                    DBMS_LOB.WRITEAPPEND(v_json_clob, 1, CHR(10)); 
                END IF;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN EXIT;
            END;
        END LOOP;
        UTL_FILE.FCLOSE(f_handle);
    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(f_handle) THEN UTL_FILE.FCLOSE(f_handle); END IF;
            IF v_json_clob IS NOT NULL THEN DBMS_LOB.FREETEMPORARY(v_json_clob); END IF;
            RAISE;
    END;
    
    -- Импорт данных в таблицу PRODUCTS с учетом всех полей
    INSERT INTO PRODUCTS (
        NAME, 
        CATEGORY_ID, 
        SUPPLIER_ID, 
        PRICE, 
        QUANTITY_IN_STOCK, 
        IS_ACTIVE, 
        DESCRIPTION
    )
    SELECT 
        jt.name,
        jt.category_id,
        jt.supplier_id,
        jt.price,
        jt.quantity_in_stock,
        NVL(jt.is_active, 'Y'), -- По умолчанию 'Y', если не указано
        jt.description
    FROM JSON_TABLE(v_json_clob, '$[*]'
        COLUMNS (
            name              VARCHAR2(100) PATH '$.name',
            category_id       NUMBER        PATH '$.category_id',
            supplier_id       NUMBER        PATH '$.supplier_id',
            price             NUMBER(10,2)  PATH '$.price',
            quantity_in_stock NUMBER        PATH '$.quantity_in_stock',
            is_active         CHAR(1)       PATH '$.is_active',
            description       VARCHAR2(1000) PATH '$.description'
        )
    ) jt;
    
    -- Проверяем существование категорий и поставщиков
    FOR rec IN (
        SELECT DISTINCT p.CATEGORY_ID 
        FROM PRODUCTS p
        LEFT JOIN CATEGORIES c ON p.CATEGORY_ID = c.CATEGORY_ID
        WHERE c.CATEGORY_ID IS NULL
    ) LOOP
        AUTOPARTS_UTIL.RAISE_ERR(-20803, 
            'Категория с ID=' || rec.CATEGORY_ID || ' не существует');
    END LOOP;
    
    FOR rec IN (
        SELECT DISTINCT p.SUPPLIER_ID 
        FROM PRODUCTS p
        LEFT JOIN SUPPLIERS s ON p.SUPPLIER_ID = s.SUPPLIER_ID
        WHERE s.SUPPLIER_ID IS NULL
    ) LOOP
        AUTOPARTS_UTIL.RAISE_ERR(-20804, 
            'Поставщик с ID=' || rec.SUPPLIER_ID || ' не существует');
    END LOOP;

    DBMS_LOB.FREETEMPORARY(v_json_clob); 
    COMMIT;

    AUTOPARTS_UTIL.LOG_ACTIVITY('import_json', 
        'Импорт товаров из '||p_filename||' завершен. Добавлено: '||SQL%ROWCOUNT||' записей.');
    DBMS_OUTPUT.PUT_LINE('Импорт завершен успешно. Добавлено '||SQL%ROWCOUNT||' товаров.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        IF v_json_clob IS NOT NULL THEN DBMS_LOB.FREETEMPORARY(v_json_clob); END IF;
        AUTOPARTS_UTIL.RAISE_ERR(-20802, 'Ошибка импорта товаров: ' || SQLERRM);
END import_products_json;

PROCEDURE clear_products IS
    v_count_orders NUMBER;
    v_count_carts  NUMBER;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
    
    -- Проверяем, есть ли товары в заказах
    SELECT COUNT(*) INTO v_count_orders 
    FROM ORDER_ITEMS oi
    JOIN PRODUCTS p ON oi.PRODUCT_ID = p.PRODUCT_ID;
    
    -- Проверяем, есть ли товары в корзинах
    SELECT COUNT(*) INTO v_count_carts 
    FROM CART_ITEMS ci
    JOIN PRODUCTS p ON ci.PRODUCT_ID = p.PRODUCT_ID;
    
    IF v_count_orders > 0 OR v_count_carts > 0 THEN
        DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: Невозможно очистить каталог товаров!');
        DBMS_OUTPUT.PUT_LINE('Найдено товаров в заказах: ' || v_count_orders);
        DBMS_OUTPUT.PUT_LINE('Найдено товаров в корзинах: ' || v_count_carts);
        DBMS_OUTPUT.PUT_LINE('Рекомендуется деактивировать товары (IS_ACTIVE = ''N'').');
        AUTOPARTS_UTIL.RAISE_ERR(-20805, 
            'Товары используются в заказах или корзинах. Очистка невозможна.');
    END IF;
    
    -- Если проверки пройдены, удаляем товары
    DELETE FROM PRODUCTS;
    COMMIT;
    
    AUTOPARTS_UTIL.LOG_ACTIVITY('clear_products', 'Каталог товаров полностью очищен.');
    DBMS_OUTPUT.PUT_LINE('Каталог товаров полностью очищен.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        AUTOPARTS_UTIL.RAISE_ERR(-20806, 'Ошибка при очистке товаров: ' || SQLERRM);
END clear_products;



    PROCEDURE print_table_products IS
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || RPAD('NAME', 30) || RPAD('PRICE', 10) || 'STOCK');
        -- Внутри AUTOPARTS_API_ADMIN.print_table_products
        FOR r IN (
            SELECT p.*, c.NAME as CAT_NAME, p.IS_ACTIVE as PROD_STAT, c.IS_ACTIVE as CAT_STAT
            FROM PRODUCTS p 
            JOIN CATEGORIES c ON p.CATEGORY_ID = c.CATEGORY_ID
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(r.NAME || ' [' || r.PROD_STAT || '/' || r.CAT_STAT || ']');
        END LOOP;
    END;

    PROCEDURE EXPORT_LOGS_JSON(p_filename IN VARCHAR2) IS
        f_handle    UTL_FILE.FILE_TYPE;
        v_json_clob CLOB;
        v_row_count NUMBER := 0;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Проверяем существование директории
        BEGIN
            f_handle := UTL_FILE.FOPEN('DATA_EXPORT_DIR', p_filename, 'W', 32767);
            UTL_FILE.FCLOSE(f_handle);
        EXCEPTION
            WHEN OTHERS THEN
                AUTOPARTS_UTIL.RAISE_ERR(-20901, 
                    'Не удалось открыть файл для записи. Проверьте директорию DATA_EXPORT_DIR: ' || SQLERRM);
        END;
        
        -- Получаем все данные из ACTIVITY_LOGS и преобразуем в JSON
        SELECT JSON_ARRAYAGG(
                   JSON_OBJECT(
                       'log_id'     VALUE LOG_ID,
                       'username'   VALUE USERNAME,
                       'action'     VALUE ACTION,
                       'details'    VALUE DETAILS,
                       'log_date'   VALUE TO_CHAR(LOG_DATE, 'YYYY-MM-DD HH24:MI:SS')
                   ) RETURNING CLOB
               ),
               COUNT(*)
        INTO v_json_clob, v_row_count
        FROM ACTIVITY_LOGS;
        
        -- Если логов нет, создаем пустой JSON массив
        IF v_json_clob IS NULL THEN
            v_json_clob := '[]';
        END IF;
        
        -- Записываем JSON в файл
        f_handle := UTL_FILE.FOPEN('DATA_EXPORT_DIR', p_filename, 'W', 32767);
        
        DECLARE
            v_offset NUMBER := 1;
            v_chunk  VARCHAR2(32767);
            v_buffer NUMBER := 32000;
        BEGIN
            LOOP
                EXIT WHEN v_offset > DBMS_LOB.GETLENGTH(v_json_clob);
                v_chunk := DBMS_LOB.SUBSTR(v_json_clob, v_buffer, v_offset);
                UTL_FILE.PUT(f_handle, v_chunk);
                v_offset := v_offset + v_buffer;
            END LOOP;
        END;
        
        UTL_FILE.FCLOSE(f_handle);
        
        -- Логируем действие
        AUTOPARTS_UTIL.LOG_ACTIVITY('export_logs_json', 
            'Экспорт логов в файл: ' || p_filename || '. Записей: ' || v_row_count);
        
        DBMS_OUTPUT.PUT_LINE('  Экспорт логов завершен успешно.');
        DBMS_OUTPUT.PUT_LINE('  Файл: ' || p_filename);
        DBMS_OUTPUT.PUT_LINE('  Записей экспортировано: ' || v_row_count);
        
    EXCEPTION
        WHEN OTHERS THEN
            IF UTL_FILE.IS_OPEN(f_handle) THEN 
                UTL_FILE.FCLOSE(f_handle); 
            END IF;
            AUTOPARTS_UTIL.RAISE_ERR(-20902, 'Ошибка экспорта логов: ' || SQLERRM);
    END EXPORT_LOGS_JSON;

    ----------------------------------------------------------------------------
    -- ИМПОРТ ЛОГОВ ДЕЯТЕЛЬНОСТИ ИЗ JSON
    ----------------------------------------------------------------------------
    PROCEDURE IMPORT_LOGS_JSON(p_filename IN VARCHAR2) IS
        f_handle    UTL_FILE.FILE_TYPE;
        v_line      VARCHAR2(32767);
        v_json_clob CLOB;
        v_imported_count NUMBER := 0;
        v_max_log_id NUMBER;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Читаем файл
        BEGIN
            f_handle := UTL_FILE.FOPEN('DATA_EXPORT_DIR', p_filename, 'R', 32767);
            DBMS_LOB.CREATETEMPORARY(v_json_clob, TRUE);
            
            LOOP
                BEGIN
                    UTL_FILE.GET_LINE(f_handle, v_line);
                    IF v_line IS NOT NULL THEN
                        DBMS_LOB.WRITEAPPEND(v_json_clob, LENGTH(v_line), v_line);
                    END IF;
                EXCEPTION
                    WHEN NO_DATA_FOUND THEN EXIT;
                END;
            END LOOP;
            
            UTL_FILE.FCLOSE(f_handle);
            
        EXCEPTION
            WHEN OTHERS THEN
                IF UTL_FILE.IS_OPEN(f_handle) THEN 
                    UTL_FILE.FCLOSE(f_handle); 
                END IF;
                IF v_json_clob IS NOT NULL THEN 
                    DBMS_LOB.FREETEMPORARY(v_json_clob); 
                END IF;
                AUTOPARTS_UTIL.RAISE_ERR(-20903, 
                    'Не удалось прочитать файл ' || p_filename || ': ' || SQLERRM);
        END;
        
        -- Получаем максимальный ID для предотвращения конфликтов
        SELECT NVL(MAX(LOG_ID), 0) INTO v_max_log_id FROM ACTIVITY_LOGS;
        
        -- Импортируем данные
        INSERT INTO ACTIVITY_LOGS (LOG_ID, USERNAME, ACTION, DETAILS, LOG_DATE)
        SELECT 
            v_max_log_id + ROWNUM, -- Генерируем новые уникальные ID
            jt.username,
            jt.action,
            jt.details,
            TO_DATE(jt.log_date, 'YYYY-MM-DD HH24:MI:SS')
        FROM JSON_TABLE(v_json_clob, '$[*]'
            COLUMNS (
                username   VARCHAR2(50)   PATH '$.username',
                action     VARCHAR2(100)  PATH '$.action',
                details    VARCHAR2(4000) PATH '$.details',
                log_date   VARCHAR2(20)   PATH '$.log_date'
            )
        ) jt;
        
        v_imported_count := SQL%ROWCOUNT;
        
        -- Очищаем временные объекты
        DBMS_LOB.FREETEMPORARY(v_json_clob);
        
        COMMIT;
        
        -- Логируем действие импорта
        AUTOPARTS_UTIL.LOG_ACTIVITY('import_logs_json', 
            'Импорт логов из файла: ' || p_filename || '. Записей импортировано: ' || v_imported_count);
        
        DBMS_OUTPUT.PUT_LINE('  Импорт логов завершен успешно.');
        DBMS_OUTPUT.PUT_LINE('  Файл: ' || p_filename);
        DBMS_OUTPUT.PUT_LINE('  Записей импортировано: ' || v_imported_count);
        DBMS_OUTPUT.PUT_LINE('  Начальный ID: ' || (v_max_log_id + 1));
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            IF v_json_clob IS NOT NULL THEN 
                DBMS_LOB.FREETEMPORARY(v_json_clob); 
            END IF;
            AUTOPARTS_UTIL.RAISE_ERR(-20904, 'Ошибка импорта логов: ' || SQLERRM);
    END IMPORT_LOGS_JSON;

    ----------------------------------------------------------------------------
    -- ОЧИСТКА ТАБЛИЦЫ ACTIVITY_LOGS
    ----------------------------------------------------------------------------
    PROCEDURE CLEAR_ACTIVITY_LOGS IS
        v_log_count NUMBER;
        v_backup_filename VARCHAR2(100);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('ADMIN');
        
        -- Получаем количество записей для логирования
        SELECT COUNT(*) INTO v_log_count FROM ACTIVITY_LOGS;
        
        -- Создаем имя файла для автоматического бекапа
        v_backup_filename := 'logs_backup_' || TO_CHAR(SYSDATE, 'YYYYMMDD_HH24MISS') || '.json';
        
        -- Автоматически создаем бекап перед очисткой
        IF v_log_count > 0 THEN
            EXPORT_LOGS_JSON(v_backup_filename);
            DBMS_OUTPUT.PUT_LINE('  Автоматический бекап создан: ' || v_backup_filename);
        END IF;
        
        -- Очищаем таблицу
        DELETE FROM ACTIVITY_LOGS;
        v_log_count := SQL%ROWCOUNT;
        
        -- Сбрасываем sequence если используется (для Oracle 12c+)
        BEGIN
            EXECUTE IMMEDIATE 'DROP SEQUENCE LOGS_SEQ';
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        
        BEGIN
            EXECUTE IMMEDIATE 'CREATE SEQUENCE LOGS_SEQ START WITH 1 INCREMENT BY 1';
        EXCEPTION
            WHEN OTHERS THEN NULL;
        END;
        
        COMMIT;
        
        -- Логируем действие очистки (после очистки, поэтому запись не появится в таблице)
        -- Вместо этого выводим сообщение
        DBMS_OUTPUT.PUT_LINE('  Таблица ACTIVITY_LOGS полностью очищена.');
        DBMS_OUTPUT.PUT_LINE('  Удалено записей: ' || v_log_count);
        DBMS_OUTPUT.PUT_LINE('  Бекап сохранен в: ' || v_backup_filename);
        
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            AUTOPARTS_UTIL.RAISE_ERR(-20905, 'Ошибка при очистке логов: ' || SQLERRM);
    END CLEAR_ACTIVITY_LOGS;

END AUTOPARTS_API_ADMIN;
/