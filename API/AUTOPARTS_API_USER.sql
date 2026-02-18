CREATE OR REPLACE PACKAGE AUTOPARTS_API_USER AS
    -- Авторизация и Регистрация
    PROCEDURE login_user(p_username IN VARCHAR2, p_password IN VARCHAR2);
    PROCEDURE register_user(p_username IN VARCHAR2, p_password IN VARCHAR2, p_first IN VARCHAR2, p_last IN VARCHAR2, p_email IN VARCHAR2, p_phone IN VARCHAR2);

    -- Каталог товаров
    PROCEDURE get_all_catalog;
    PROCEDURE get_all_categories;
    PROCEDURE print_products_by_category(p_cat_id_str IN VARCHAR2);
    
    -- Управление корзиной
    PROCEDURE show_cart(p_user_id_str IN VARCHAR2);
    PROCEDURE add_to_cart(p_user_id_str IN VARCHAR2, p_prod_id_str IN VARCHAR2, p_qty_str IN VARCHAR2);
    PROCEDURE change_count_cart(p_user_id_str IN VARCHAR2, p_row_number_str IN VARCHAR2, p_qty_str IN VARCHAR2);
    PROCEDURE remove_from_cart(p_user_id_str IN VARCHAR2, p_row_number_str IN VARCHAR2);
    
    -- Оформление заказа
    PROCEDURE start_checkout(p_user_id_str IN VARCHAR2);
    PROCEDURE add_delivery_info(p_user_id_str IN VARCHAR2, p_address IN VARCHAR2, p_date_str IN VARCHAR2);
    PROCEDURE CREATE_ORDER_FROM_CART(p_user_id_str IN VARCHAR2);
    PROCEDURE user_orders(p_user_id_str IN VARCHAR2);
    
    -- Аналитика
    PROCEDURE trending_products;
END AUTOPARTS_API_USER;
/


CREATE OR REPLACE PACKAGE BODY AUTOPARTS_API_USER AS

   
    -- Внутренняя функция: Безопасное преобразование строки в число
    FUNCTION to_num(p_val IN VARCHAR2, p_field_name IN VARCHAR2) RETURN NUMBER IS
    BEGIN
        -- Заменяем запятую на точку на случай разной локали, удаляем пробелы
        RETURN TO_NUMBER(TRIM(REPLACE(p_val, ',', '.')));
    EXCEPTION
        WHEN OTHERS THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20001, 'Ошибка: Поле "' || p_field_name || '" должно быть числом. Вы ввели: "' || p_val || '"');
    END;

    FUNCTION to_date_safe(p_val IN VARCHAR2) RETURN DATE IS
        v_date DATE;
    BEGIN
        -- Поддержка форматов с точкой и дефисом
        BEGIN
            v_date := TO_DATE(p_val, 'DD-MM-YYYY');
        EXCEPTION WHEN OTHERS THEN
            v_date := TO_DATE(p_val, 'DD.MM.YYYY');
        END;

        -- Проверка: Дата не может быть в прошлом
        IF TRUNC(v_date) < TRUNC(SYSDATE) THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20003, 'Ошибка: Нельзя назначить доставку на прошедшую дату.');
        END IF;

        RETURN v_date;
    EXCEPTION
        WHEN OTHERS THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20002, 'Ошибка: Неверный формат даты. Используйте: ДД-ММ-ГГГГ');
    END;

    ----------------------------------------------------------------------------
    -- ЛОГИН И РЕГИСТРАЦИЯ
    ----------------------------------------------------------------------------
    PROCEDURE login_user(p_username IN VARCHAR2, p_password IN VARCHAR2) IS
        v_stored VARCHAR2(64);
        v_blocked CHAR(1);
    BEGIN
        BEGIN
            SELECT PASSWORD_HASH, IS_BLOCKED INTO v_stored, v_blocked FROM USERS WHERE USERNAME = p_username;
        EXCEPTION WHEN NO_DATA_FOUND THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20716, 'Пользователь с таким логином не найден.');
        END;
        
        IF v_blocked = 'Y' THEN AUTOPARTS_UTIL.RAISE_ERR(-20717, 'Учетная запись заблокирована.'); END IF;
        
        IF AUTOPARTS_UTIL.HASH_PASS(p_password) != v_stored THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20718, 'Неверный пароль.'); 
        END IF;
        
        DBMS_OUTPUT.PUT_LINE('Вход выполнен успешно. Добро пожаловать, ' || p_username || '!');
        AUTOPARTS_UTIL.LOG_ACTIVITY('login', 'User logged in: ' || p_username);
    END;

    PROCEDURE register_user(p_username IN VARCHAR2, p_password IN VARCHAR2, p_first IN VARCHAR2, p_last IN VARCHAR2, p_email IN VARCHAR2, p_phone IN VARCHAR2) IS
        v_uid NUMBER;
    BEGIN
        INSERT INTO USERS (USERNAME, PASSWORD_HASH, FIRST_NAME, LAST_NAME, EMAIL, PHONE, ROLE)
        VALUES (p_username, AUTOPARTS_UTIL.HASH_PASS(p_password), p_first, p_last, p_email, p_phone, 'user')
        RETURNING USER_ID INTO v_uid;
        
        INSERT INTO SHOPPING_CARTS (USER_ID) VALUES (v_uid);
        
        COMMIT; -- Фиксация транзакции
        DBMS_OUTPUT.PUT_LINE('Пользователь ' || p_username || ' успешно зарегистрирован (ID: ' || v_uid || ').');
        AUTOPARTS_UTIL.LOG_ACTIVITY('register', 'New user: ' || p_username);
    EXCEPTION 
        WHEN DUP_VAL_ON_INDEX THEN 
            ROLLBACK;
            AUTOPARTS_UTIL.RAISE_ERR(-20719, 'Логин или Email уже заняты другим пользователем.');
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END;

    ----------------------------------------------------------------------------
    -- КАТАЛОГ
    ----------------------------------------------------------------------------
    PROCEDURE get_all_catalog IS
        v_found BOOLEAN := FALSE;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ПОЛНЫЙ КАТАЛОГ ТОВАРОВ');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('ID', 6) || ' | ' || 
            RPAD('НАЗВАНИЕ', 35) || ' | ' || 
            RPAD('КАТЕГОРИЯ', 20) || ' | ' || 
            RPAD('ОСТАТОК', 10) || ' | ' || 
            'ЦЕНА'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));
    
        FOR r IN (
            SELECT p.product_id, p.name, c.name as cat, p.price, p.quantity_in_stock 
            FROM PRODUCTS p 
            JOIN CATEGORIES c ON p.category_id = c.category_id
            WHERE p.IS_ACTIVE = 'Y'          -- Только активные товары
              AND c.IS_ACTIVE = 'Y'          -- Только активные категории
              AND p.quantity_in_stock > 0    -- Только в наличии
            ORDER BY c.name, p.name
        ) LOOP
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.product_id, 6) || ' | ' || 
                RPAD(SUBSTR(r.name, 1, 35), 35) || ' | ' || 
                RPAD(SUBSTR(r.cat, 1, 20), 20) || ' | ' || 
                RPAD(r.quantity_in_stock || ' шт.', 10) || ' | ' || 
                TO_CHAR(r.price, '999G990D00') || ' р.'
            );
        END LOOP;
    
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('В данный момент доступных товаров нет.');
        END IF;
    
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 100, '-'));
    END get_all_catalog;
    
    PROCEDURE get_all_categories IS
    v_found BOOLEAN := FALSE;
    v_is_admin BOOLEAN := FALSE;
BEGIN
    -- Проверяем права доступа (минимум USER)
    AUTOPARTS_UTIL.CHECK_ACCESS('USER');
    
    -- Проверяем, является ли пользователь администратором
    DECLARE
        v_user_role VARCHAR2(20);
    BEGIN
        SELECT ROLE INTO v_user_role 
        FROM USERS 
        WHERE USERNAME = SYS_CONTEXT('USERENV', 'SESSION_USER');
        
        v_is_admin := (v_user_role = 'admin');
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            v_is_admin := FALSE;
    END;
    
    IF v_is_admin THEN
        -- Вывод для администратора: ВСЕ категории с статусами
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'СПИСОК ВСЕХ КАТЕГОРИЙ (АДМИНИСТРАТОР)');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 55, '-'));
        DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || ' | ' || 
                            RPAD('НАЗВАНИЕ', 35) || ' | ' || 
                            RPAD('СТАТУС', 10));
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 55, '-'));
        
        FOR r IN (
            SELECT category_id, name, 
                   CASE WHEN is_active = 'Y' THEN 'АКТИВНА' 
                        ELSE 'НЕАКТИВНА' END as status,
                   is_active
            FROM CATEGORIES 
            ORDER BY is_active DESC, category_id  -- Сначала активные, потом неактивные
        ) LOOP
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.category_id, 5) || ' | ' || 
                RPAD(SUBSTR(r.name, 1, 35), 35) || ' | ' || 
                RPAD(r.status, 10)
            );
        END LOOP;
        
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('Категорий нет.');
        END IF;
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 55, '-'));
        
        -- Статистика для администратора
        DECLARE
            v_total_count NUMBER;
            v_active_count NUMBER;
            v_inactive_count NUMBER;
        BEGIN
            SELECT COUNT(*),
                   COUNT(CASE WHEN is_active = 'Y' THEN 1 END),
                   COUNT(CASE WHEN is_active = 'N' THEN 1 END)
            INTO v_total_count, v_active_count, v_inactive_count
            FROM CATEGORIES;
            
            DBMS_OUTPUT.PUT_LINE('Всего категорий: ' || v_total_count);
            DBMS_OUTPUT.PUT_LINE('Активных: ' || v_active_count);
            DBMS_OUTPUT.PUT_LINE('Неактивных: ' || v_inactive_count);
        END;
        
    ELSE
        -- Вывод для обычных пользователей: ТОЛЬКО активные категории
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'СПИСОК КАТЕГОРИЙ');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 45, '-'));
        DBMS_OUTPUT.PUT_LINE(RPAD('ID', 5) || ' | ' || 
                            RPAD('НАЗВАНИЕ', 35));
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 45, '-'));
        
        FOR r IN (
            SELECT category_id, name
            FROM CATEGORIES 
            WHERE IS_ACTIVE = 'Y'
            ORDER BY category_id
        ) LOOP
            v_found := TRUE;
            DBMS_OUTPUT.PUT_LINE(
                RPAD(r.category_id, 5) || ' | ' || 
                SUBSTR(r.name, 1, 35)
            );
        END LOOP;
        
        IF NOT v_found THEN
            DBMS_OUTPUT.PUT_LINE('Категорий нет.');
        END IF;
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 45, '-'));
        
        -- Простая статистика для пользователей
        DECLARE
            v_count NUMBER;
        BEGIN
            SELECT COUNT(*) INTO v_count 
            FROM CATEGORIES 
            WHERE IS_ACTIVE = 'Y';
            
            DBMS_OUTPUT.PUT_LINE('Всего категорий: ' || v_count);
        END;
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Ошибка при получении списка категорий: ' || SQLERRM);
END get_all_categories;
    
    PROCEDURE print_products_by_category(p_cat_id_str IN VARCHAR2) IS
    v_cid NUMBER := to_num(p_cat_id_str, 'ID Категории');
    v_cname VARCHAR2(100);
    v_cat_active CHAR(1);
    v_found BOOLEAN := FALSE;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('USER');
    
    -- Проверяем существование и активность категории
    BEGIN
        SELECT name, is_active INTO v_cname, v_cat_active 
        FROM CATEGORIES WHERE category_id = v_cid;
    EXCEPTION WHEN NO_DATA_FOUND THEN 
        AUTOPARTS_UTIL.RAISE_ERR(-20701, 'Категория с ID ' || v_cid || ' не найдена.'); 
    END;

    -- Проверяем активность категории
    IF v_cat_active = 'N' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20102, 
            'Категория "' || v_cname || '" временно не обслуживается.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'КАТЕГОРИЯ: ' || UPPER(v_cname));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
    DBMS_OUTPUT.PUT_LINE(
        RPAD('ID', 6) || ' | ' || 
        RPAD('НАЗВАНИЕ ТОВАРА', 35) || ' | ' || 
        RPAD('НАЛИЧИЕ', 10) || ' | ' || 
        RPAD('СТАТУС', 10) || ' | ' || 
        'ЦЕНА'
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

    FOR r IN (
        SELECT product_id, name, quantity_in_stock, price, is_active,
               CASE WHEN is_active = 'Y' THEN 'АКТИВЕН' 
                    ELSE 'НЕАКТИВЕН' END as status_display
        FROM PRODUCTS 
        WHERE category_id = v_cid 
          AND IS_ACTIVE = 'Y'  -- Только активные товары
        ORDER BY name
    ) LOOP
        v_found := TRUE;
        DBMS_OUTPUT.PUT_LINE(
            RPAD(r.product_id, 6) || ' | ' || 
            RPAD(SUBSTR(r.name, 1, 35), 35) || ' | ' || 
            RPAD(r.quantity_in_stock || ' шт.', 10) || ' | ' || 
            RPAD(r.status_display, 10) || ' | ' || 
            TO_CHAR(r.price, '999G990D00') || ' р.'
        );
    END LOOP;

    IF NOT v_found THEN
        DBMS_OUTPUT.PUT_LINE('В этой категории нет активных товаров.');
    END IF;
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));
END print_products_by_category;
    ----------------------------------------------------------------------------
    -- КОРЗИНА
    ----------------------------------------------------------------------------
    PROCEDURE show_cart(p_user_id_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
        v_cart_id NUMBER;
        v_total NUMBER := 0;
        v_idx NUMBER := 0; 
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
        
        SELECT CART_ID INTO v_cart_id FROM SHOPPING_CARTS WHERE USER_ID = v_uid;
    
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'СОДЕРЖИМОЕ КОРЗИНЫ (ID Пользователя: ' || v_uid || ')');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 65, '-'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('№', 4) || ' | ' || 
            RPAD('НАЗВАНИЕ ТОВАРА', 30) || ' | ' || 
            RPAD('КОЛ-ВО', 10) || ' | ' || 
            'СУММА'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 65, '-'));
    
        FOR r IN (
            SELECT p.NAME, ci.QUANTITY, (p.PRICE * ci.QUANTITY) as line_sum
            FROM CART_ITEMS ci
            JOIN PRODUCTS p ON ci.PRODUCT_ID = p.PRODUCT_ID
            WHERE ci.CART_ID = v_cart_id
            ORDER BY ci.CART_ITEM_ID -- Сортировка важна для стабильности номеров
        ) LOOP
            v_idx := v_idx + 1;
            v_total := v_total + r.line_sum;
            
            DBMS_OUTPUT.PUT_LINE(
                RPAD(v_idx, 4) || ' | ' || 
                RPAD(SUBSTR(r.NAME, 1, 30), 30) || ' | ' || 
                RPAD(r.QUANTITY || ' шт.', 10) || ' | ' || 
                r.line_sum || ' р.'
            );
        END LOOP;
    
        IF v_idx = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Ваша корзина пуста.');
        ELSE
            DBMS_OUTPUT.PUT_LINE(RPAD('-', 65, '-'));
            DBMS_OUTPUT.PUT_LINE('ИТОГО К ОПЛАТЕ: ' || v_total || ' р.');
        END IF;
    END;

    

    PROCEDURE check_cart_not_locked(p_cart_id IN NUMBER) IS
        v_status CHAR(1);
        v_user_id NUMBER;
        v_username VARCHAR2(50);
    BEGIN
        SELECT sc.STATUS, sc.USER_ID, u.USERNAME
        INTO v_status, v_user_id, v_username
        FROM SHOPPING_CARTS sc
        JOIN USERS u ON sc.USER_ID = u.USER_ID
        WHERE sc.CART_ID = p_cart_id;
        
        IF v_status = 'Y' THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20720, 
                'Корзина пользователя ' || v_username || ' (ID: ' || v_user_id || ') ' ||
                'заблокирована, так как начато оформление заказа. ' ||
                'Завершите оформление текущего заказа.');
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20765, 'Корзина не найдена.');
    END check_cart_not_locked;

    ----------------------------------------------------------------------------
    -- УПРАВЛЕНИЕ КОРЗИНОЙ (ИСПРАВЛЕННЫЕ ПРОЦЕДУРЫ)
    ----------------------------------------------------------------------------
    PROCEDURE add_to_cart(p_user_id_str IN VARCHAR2, p_prod_id_str IN VARCHAR2, p_qty_str IN VARCHAR2) IS
    v_uid NUMBER;
    v_pid NUMBER;
    v_qty NUMBER;
    
    v_cart_id         NUMBER;
    v_stock           NUMBER;
    v_prod_active     CHAR(1);
    v_cat_active      CHAR(1);
    v_sup_active      CHAR(1);
    v_current_in_cart NUMBER := 0;
    v_product_name    VARCHAR2(100);
    v_category_name   VARCHAR2(100);
    v_supplier_name   VARCHAR2(100);
    v_price           NUMBER(10,2);
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('USER');
    
    -- Валидация входных параметров
    IF p_user_id_str IS NULL OR TRIM(p_user_id_str) = '' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20755, 'ID пользователя не может быть пустым.');
    END IF;
    
    IF p_prod_id_str IS NULL OR TRIM(p_prod_id_str) = '' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20756, 'ID товара не может быть пустым.');
    END IF;
    
    IF p_qty_str IS NULL OR TRIM(p_qty_str) = '' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20757, 'Количество не может быть пустым.');
    END IF;
    
    -- Конвертация параметров
    v_uid := to_num(p_user_id_str, 'ID Пользователя');
    v_pid := to_num(p_prod_id_str, 'ID Товара');
    v_qty := to_num(p_qty_str, 'Количество');
    
    -- Проверка количества
    IF v_qty <= 0 THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20758, 'Количество должно быть больше 0.');
    END IF;
    
    IF v_qty > 100 THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20759, 'Нельзя добавить более 100 единиц одного товара за раз.');
    END IF;
    
    -- 1. Проверяем существование и активность пользователя
    DECLARE
        v_user_active CHAR(1);
        v_user_blocked CHAR(1);
    BEGIN
        SELECT IS_ACTIVE, IS_BLOCKED INTO v_user_active, v_user_blocked
        FROM USERS WHERE USER_ID = v_uid;
        
        IF v_user_active = 'N' THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20760, 'Ваш аккаунт деактивирован.');
        END IF;
        
        IF v_user_blocked = 'Y' THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20761, 'Ваш аккаунт заблокирован.');
        END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20762, 'Пользователь с ID ' || v_uid || ' не найден.');
    END;
    
    -- 2. Получаем ID корзины пользователя
    BEGIN
        SELECT CART_ID INTO v_cart_id 
        FROM SHOPPING_CARTS 
        WHERE USER_ID = v_uid;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20763, 'Корзина для пользователя ID ' || v_uid || ' не найдена.');
    END;

    -- 3. ПРОВЕРКА БЛОКИРОВКИ (если корзина в процессе оформления)
    check_cart_not_locked(v_cart_id);

    -- 4. ПРОВЕРКА ДОСТУПНОСТИ ТОВАРА (Товар + Категория + Поставщик + Наличие)
    BEGIN
        SELECT p.NAME, p.QUANTITY_IN_STOCK, p.IS_ACTIVE, p.PRICE,
               c.NAME, c.IS_ACTIVE,
               s.COMPANY_NAME, s.IS_ACTIVE
        INTO v_product_name, v_stock, v_prod_active, v_price,
             v_category_name, v_cat_active,
             v_supplier_name, v_sup_active
        FROM PRODUCTS p
        JOIN CATEGORIES c ON p.CATEGORY_ID = c.CATEGORY_ID
        JOIN SUPPLIERS s ON p.SUPPLIER_ID = s.SUPPLIER_ID
        WHERE p.PRODUCT_ID = v_pid;
    EXCEPTION 
        WHEN NO_DATA_FOUND THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20703, 'Товар с ID ' || v_pid || ' не найден в базе.');
    END;

    -- Детальная проверка доступности товара:
    IF v_prod_active = 'N' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20101, 
            'Товар "' || v_product_name || '" снят с продажи и недоступен для заказа.');
    END IF;

    IF v_cat_active = 'N' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20102, 
            'Категория "' || v_category_name || '" временно не обслуживается. ' ||
            'Товар "' || v_product_name || '" недоступен.');
    END IF;

    IF v_sup_active = 'N' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20106, 
            'Поставщик "' || v_supplier_name || '" временно не работает. ' ||
            'Товар "' || v_product_name || '" недоступен.');
    END IF;

    IF v_stock <= 0 THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20103, 
            'Товар "' || v_product_name || '" отсутствует на складе.');
    END IF;
    
    -- Проверка, что товар не закончился прямо сейчас
    IF v_stock < v_qty THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20107, 
            'Недостаточно товара "' || v_product_name || '" на складе. ' ||
            'Доступно: ' || v_stock || ' шт., запрошено: ' || v_qty || ' шт.');
    END IF;

    -- 5. Проверяем, сколько этого товара УЖЕ лежит в корзине пользователя
    BEGIN
        SELECT QUANTITY INTO v_current_in_cart 
        FROM CART_ITEMS 
        WHERE CART_ID = v_cart_id AND PRODUCT_ID = v_pid;
    EXCEPTION WHEN NO_DATA_FOUND THEN 
        v_current_in_cart := 0;
    END;

    -- 6. Проверка общего остатка (учитывая уже в корзине)
    IF (v_current_in_cart + v_qty) > v_stock THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20705, 
            'Недостаточно товара "' || v_product_name || '". ' ||
            'На складе: ' || v_stock || ' шт. ' ||
            'В вашей корзине уже: ' || v_current_in_cart || ' шт. ' ||
            'Вы пытаетесь добавить еще: ' || v_qty || ' шт.');
    END IF;
    
    -- 7. Проверка максимального количества товаров в корзине (чтобы избежать злоупотреблений)
    DECLARE
        v_total_items_in_cart NUMBER;
        v_max_items CONSTANT NUMBER := 50; -- Максимум 50 разных товаров в корзине
    BEGIN
        SELECT COUNT(DISTINCT PRODUCT_ID) INTO v_total_items_in_cart
        FROM CART_ITEMS 
        WHERE CART_ID = v_cart_id;
        
        IF v_current_in_cart = 0 AND v_total_items_in_cart >= v_max_items THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20764, 
                'В корзине слишком много разных товаров (максимум ' || v_max_items || '). ' ||
                'Удалите некоторые товары перед добавлением новых.');
        END IF;
    END;

    -- 8. Добавление или обновление количества в корзине (ИСПРАВЛЕНО)
    MERGE INTO CART_ITEMS ci
    USING dual ON (ci.cart_id = v_cart_id AND ci.product_id = v_pid)
    WHEN MATCHED THEN 
        UPDATE SET ci.quantity = ci.quantity + v_qty
    WHEN NOT MATCHED THEN 
        INSERT (CART_ID, PRODUCT_ID, QUANTITY)  -- CART_ITEM_ID сгенерится автоматически
        VALUES (v_cart_id, v_pid, v_qty);
        
    COMMIT;
    
    -- 9. Информационное сообщение
    DBMS_OUTPUT.PUT_LINE('✓ Товар успешно добавлен в корзину!');
    DBMS_OUTPUT.PUT_LINE('  Товар: ' || v_product_name);
    DBMS_OUTPUT.PUT_LINE('  Категория: ' || v_category_name);
    DBMS_OUTPUT.PUT_LINE('  Цена: ' || TO_CHAR(v_price, '999G990D00') || ' руб./шт.');
    DBMS_OUTPUT.PUT_LINE('  Количество: ' || v_qty || ' шт. → ' || 
                        TO_CHAR(v_price * v_qty, '999G990D00') || ' руб.');
    DBMS_OUTPUT.PUT_LINE('  Всего этого товара в корзине: ' || (v_current_in_cart + v_qty) || ' шт.');
    DBMS_OUTPUT.PUT_LINE('  Остаток на складе: ' || (v_stock - (v_current_in_cart + v_qty)) || ' шт.');
    
    -- Логирование успешного добавления
    AUTOPARTS_UTIL.LOG_ACTIVITY('add_to_cart', 
        'User ' || v_uid || ' added product ' || v_pid || 
        ' (' || v_product_name || ') x' || v_qty);
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        -- Логирование ошибки
        AUTOPARTS_UTIL.LOG_ACTIVITY('add_to_cart_error', 
            'User ' || v_uid || ' failed to add product ' || v_pid || 
            ': ' || SQLERRM);
        RAISE;
END add_to_cart;    

    PROCEDURE change_count_cart(p_user_id_str IN VARCHAR2, p_row_number_str IN VARCHAR2, p_qty_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
        v_row_target NUMBER := to_num(p_row_number_str, 'Номер строки');
        v_new_qty NUMBER := to_num(p_qty_str, 'Количество');
        
        v_cart_id NUMBER;
        v_real_item_id NUMBER := NULL;
        v_stock NUMBER;
        v_pname VARCHAR2(100);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
        SELECT CART_ID INTO v_cart_id FROM SHOPPING_CARTS WHERE USER_ID = v_uid;

        -- ПРОВЕРКА БЛОКИРОВКИ
        check_cart_not_locked(v_cart_id);

        -- Находим реальный ID записи
        SELECT cart_item_id, quantity_in_stock, product_name INTO v_real_item_id, v_stock, v_pname
        FROM (
            SELECT ci.cart_item_id, p.quantity_in_stock, p.name as product_name,
                   ROW_NUMBER() OVER (ORDER BY ci.cart_item_id) as rn
            FROM CART_ITEMS ci
            JOIN PRODUCTS p ON ci.product_id = p.product_id
            WHERE ci.cart_id = v_cart_id
        ) WHERE rn = v_row_target;

        IF v_new_qty > v_stock THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20705, 'Ошибка: На складе для "'||v_pname||'" осталось всего '||v_stock||' шт.');
        END IF;

        UPDATE CART_ITEMS SET QUANTITY = v_new_qty WHERE CART_ITEM_ID = v_real_item_id;
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Успешно: Количество товара в строке ' || v_row_target || ' изменено.');

    EXCEPTION 
        WHEN NO_DATA_FOUND THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20708, 'Ошибка: В вашей корзине нет строки под номером ' || v_row_target);
        WHEN OTHERS THEN
            RAISE;
    END;

    PROCEDURE remove_from_cart(p_user_id_str IN VARCHAR2, p_row_number_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
        v_row_target NUMBER := to_num(p_row_number_str, 'Номер строки');
        v_cart_id NUMBER;
        v_real_item_id NUMBER;
        v_pname VARCHAR2(100);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
        
        SELECT CART_ID INTO v_cart_id FROM SHOPPING_CARTS WHERE USER_ID = v_uid;

        -- ПРОВЕРКА БЛОКИРОВКИ
        check_cart_not_locked(v_cart_id);

        -- Находим внутренний ID строки
        BEGIN
            SELECT cart_item_id, product_name INTO v_real_item_id, v_pname
            FROM (
                SELECT ci.cart_item_id, p.name as product_name,
                       ROW_NUMBER() OVER (ORDER BY ci.cart_item_id) as rn
                FROM CART_ITEMS ci
                JOIN PRODUCTS p ON ci.product_id = p.product_id
                WHERE ci.cart_id = v_cart_id
            ) WHERE rn = v_row_target;
        EXCEPTION WHEN NO_DATA_FOUND THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20708, 'Ошибка: В корзине нет строки под номером ' || v_row_target);
        END;

        DELETE FROM CART_ITEMS WHERE CART_ITEM_ID = v_real_item_id;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Успешно: Товар "' || v_pname || '" (строка №' || v_row_target || ') удален.');
    END;
    
    ----------------------------------------------------------------------------
    -- ОФОРМЛЕНИЕ ЗАКАЗА
    ----------------------------------------------------------------------------
    PROCEDURE start_checkout(p_user_id_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
        UPDATE SHOPPING_CARTS SET STATUS = 'Y' WHERE USER_ID = v_uid AND STATUS = 'N';
        
        IF SQL%ROWCOUNT = 0 THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20709, 'Не удалось начать оформление (возможно, уже начато или корзина не найдена).'); 
        END IF;
        
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Процесс оформления заказа начат. Корзина заблокирована.');
    END;

    PROCEDURE ADD_DELIVERY_INFO(
    p_user_id_str IN VARCHAR2,
    p_address     IN VARCHAR2,
    p_date_str    IN VARCHAR2
) IS
    v_uid NUMBER;
    v_date DATE;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('USER');
    
    -- Валидация входных параметров
    IF p_user_id_str IS NULL OR TRIM(p_user_id_str) = '' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20743, 'ID пользователя не может быть пустым.');
    END IF;
    
    -- Конвертация ID пользователя
    BEGIN
        v_uid := TO_NUMBER(p_user_id_str);
    EXCEPTION WHEN OTHERS THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20744, 'ID пользователя должно быть числом.');
    END;
    
    -- Валидация адреса
    IF p_address IS NULL OR TRIM(p_address) = '' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20740, 'Адрес не может быть пустым.');
    ELSIF LENGTH(TRIM(p_address)) < 5 THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20745, 'Адрес должен содержать минимум 5 символов.');
    END IF;
    
    -- Конвертация даты
    IF p_date_str IS NULL OR TRIM(p_date_str) = '' THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20746, 'Дата доставки не может быть пустой.');
    END IF;
    
    BEGIN
        v_date := TO_DATE(p_date_str, 'DD-MM-YYYY');
    EXCEPTION WHEN OTHERS THEN
        BEGIN
            v_date := TO_DATE(p_date_str, 'DD.MM.YYYY'); -- Альтернативный формат
        EXCEPTION WHEN OTHERS THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20741, 
                'Неверный формат даты. Используйте ДД-ММ-ГГГГ или ДД.ММ.ГГГГ');
        END;
    END;
    
    -- Проверка, что дата не в прошлом
    IF TRUNC(v_date) < TRUNC(SYSDATE) THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20742, 
            'Дата доставки (' || TO_CHAR(v_date, 'DD.MM.YYYY') || 
            ') не может быть раньше сегодняшней даты.');
    END IF;
    
    -- Проверка, что пользователь существует и активен
    DECLARE
        v_user_active CHAR(1);
        v_user_blocked CHAR(1);
    BEGIN
        SELECT IS_ACTIVE, IS_BLOCKED 
        INTO v_user_active, v_user_blocked
        FROM USERS 
        WHERE USER_ID = v_uid;
        
        IF v_user_active = 'N' THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20747, 'Пользователь деактивирован.');
        END IF;
        
        IF v_user_blocked = 'Y' THEN
            AUTOPARTS_UTIL.RAISE_ERR(-20748, 'Пользователь заблокирован.');
        END IF;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20749, 'Пользователь с ID ' || v_uid || ' не найден.');
    END;
    
    -- Обновление корзины
    UPDATE SHOPPING_CARTS 
    SET DELIVERY_ADDRESS = p_address,
        DELIVERY_TIME = v_date
    WHERE USER_ID = v_uid AND STATUS = 'Y';
    
    IF SQL%ROWCOUNT = 0 THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20710, 
            'Сначала выполните START_CHECKOUT для пользователя ID ' || v_uid);
    END IF;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Адрес доставки сохранен для пользователя ID ' || v_uid || 
                        ': ' || p_address || ' на ' || TO_CHAR(v_date, 'DD.MM.YYYY'));
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END ADD_DELIVERY_INFO;

    
    PROCEDURE CREATE_ORDER_FROM_CART(
    p_user_id_str IN VARCHAR2
) IS
    v_uid NUMBER := TO_NUMBER(p_user_id_str);
    v_cart_id NUMBER;
    v_address VARCHAR2(255);
    v_date DATE;
    v_order_id NUMBER;
    v_total NUMBER := 0;
    v_product_name VARCHAR2(100); -- Добавленная переменная
    v_stock NUMBER;
BEGIN
    AUTOPARTS_UTIL.CHECK_ACCESS('USER');
    
    -- Получаем данные из корзины
    SELECT CART_ID, DELIVERY_ADDRESS, DELIVERY_TIME
    INTO v_cart_id, v_address, v_date
    FROM SHOPPING_CARTS 
    WHERE USER_ID = v_uid AND STATUS = 'Y';
    
    -- Проверяем, что адрес и дата указаны
    IF v_address IS NULL THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20743, 
            'Укажите адрес доставки: ADD_DELIVERY_INFO(user_id, адрес, дата)');
    END IF;
    
    IF v_date IS NULL THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20744, 
            'Укажите дату доставки: ADD_DELIVERY_INFO(user_id, адрес, дата)');
    END IF;
    
    -- Создаем заказ (всегда доставка)
    INSERT INTO ORDERS (USER_ID, STATUS, SHIPPING_ADDRESS, ORDER_DATE)
    VALUES (v_uid, 'Processing', v_address, SYSDATE)
    RETURNING ORDER_ID INTO v_order_id;
    
    -- Переносим товары из корзины
    FOR r IN (
        SELECT ci.product_id, ci.quantity, p.price, p.name as product_name
        FROM CART_ITEMS ci 
        JOIN PRODUCTS p ON ci.product_id = p.product_id 
        WHERE ci.cart_id = v_cart_id
    ) LOOP
        -- Проверяем доступность товара
        BEGIN
            SELECT QUANTITY_IN_STOCK INTO v_stock
            FROM PRODUCTS WHERE PRODUCT_ID = r.product_id;
            
            IF v_stock < r.quantity THEN
                -- Используем уже полученное имя товара
                AUTOPARTS_UTIL.RAISE_ERR(-20745,
                    'Товар "' || r.product_name || 
                    '" недостаточно на складе. Доступно: ' || v_stock || ' шт.');
            END IF;
        END;
        
        -- Добавляем в заказ
        INSERT INTO ORDER_ITEMS (ORDER_ID, PRODUCT_ID, QUANTITY, PRICE_AT_PURCHASE) 
        VALUES (v_order_id, r.product_id, r.quantity, r.price);
        
        -- Списание со склада
        UPDATE PRODUCTS 
        SET QUANTITY_IN_STOCK = QUANTITY_IN_STOCK - r.quantity 
        WHERE PRODUCT_ID = r.product_id;
        
        v_total := v_total + (r.price * r.quantity);
    END LOOP;
    
    -- Обновляем сумму заказа
    UPDATE ORDERS SET TOTAL_AMOUNT = v_total WHERE ORDER_ID = v_order_id;
    
    -- Очищаем корзину
    DELETE FROM CART_ITEMS WHERE CART_ID = v_cart_id;
    UPDATE SHOPPING_CARTS 
    SET STATUS = 'N', DELIVERY_ADDRESS = NULL, DELIVERY_TIME = NULL 
    WHERE CART_ID = v_cart_id;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Заказ №' || v_order_id || ' оформлен! Сумма: ' || v_total || ' руб.');
    DBMS_OUTPUT.PUT_LINE('Доставка по адресу: ' || v_address);
    DBMS_OUTPUT.PUT_LINE('Ориентировочная дата: ' || TO_CHAR(v_date, 'DD.MM.YYYY'));
    
EXCEPTION 
    WHEN NO_DATA_FOUND THEN
        AUTOPARTS_UTIL.RAISE_ERR(-20714, 'Сначала выполните START_CHECKOUT и ADD_DELIVERY_INFO');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END CREATE_ORDER_FROM_CART;   

    
    PROCEDURE user_orders(p_user_id_str IN VARCHAR2) IS
        v_uid NUMBER := to_num(p_user_id_str, 'ID Пользователя');
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ИСТОРИЯ ЗАКАЗОВ');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 50, '-'));
        
        FOR r IN (SELECT * FROM ORDERS WHERE USER_ID = v_uid ORDER BY ORDER_DATE DESC) LOOP
            DBMS_OUTPUT.PUT_LINE('Заказ №' || r.order_id || ' | Статус: ' || r.status || ' | Сумма: ' || r.total_amount || ' р.');
        END LOOP;
    END;

    PROCEDURE trending_products IS
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('USER');
    
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ТОП-10 ПОПУЛЯРНЫХ ТОВАРОВ');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
        DBMS_OUTPUT.PUT_LINE(RPAD('НАЗВАНИЕ ТОВАРА', 40) || ' | ПРОДАНО (шт.)');
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    
        FOR r IN (
            SELECT * FROM (
                SELECT p.NAME, SUM(oi.QUANTITY) as total_sold
                FROM ORDER_ITEMS oi JOIN PRODUCTS p ON oi.PRODUCT_ID = p.PRODUCT_ID
                GROUP BY p.NAME ORDER BY total_sold DESC
            ) WHERE ROWNUM <= 10
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(RPAD(SUBSTR(r.NAME, 1, 40), 40) || ' | ' || r.total_sold);
        END LOOP;
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 60, '-'));
    END trending_products;


END AUTOPARTS_API_USER;
/