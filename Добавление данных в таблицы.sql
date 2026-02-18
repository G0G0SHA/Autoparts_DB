SET SERVEROUTPUT ON;

DECLARE
    -- Переменные для хранения ID (чтобы не искать их вручную)
    v_cat_engine NUMBER; v_cat_susp NUMBER; v_cat_brake NUMBER; 
    v_cat_oil NUMBER; v_cat_filter NUMBER;
    v_sup_arm NUMBER; v_sup_shate NUMBER; v_sup_mon NUMBER;
    v_user_id NUMBER;
BEGIN
   
    -- 2. КАТЕГОРИИ
    INSERT INTO CATEGORIES (NAME) VALUES ('Двигатель и выхлоп') RETURNING CATEGORY_ID INTO v_cat_engine;
    INSERT INTO CATEGORIES (NAME) VALUES ('Подвеска и рулевое') RETURNING CATEGORY_ID INTO v_cat_susp;
    INSERT INTO CATEGORIES (NAME) VALUES ('Тормозная система') RETURNING CATEGORY_ID INTO v_cat_brake;
    INSERT INTO CATEGORIES (NAME) VALUES ('Масла и жидкости') RETURNING CATEGORY_ID INTO v_cat_oil;
    INSERT INTO CATEGORIES (NAME) VALUES ('Фильтры') RETURNING CATEGORY_ID INTO v_cat_filter;

    -- 3. ПОСТАВЩИКИ
    INSERT INTO SUPPLIERS (COMPANY_NAME, PHONE, EMAIL) VALUES ('Армтек', '+375172000001', 'sales@armtek.by') RETURNING SUPPLIER_ID INTO v_sup_arm;
    INSERT INTO SUPPLIERS (COMPANY_NAME, PHONE, EMAIL) VALUES ('Шате-М Плюс', '+375296005544', 'info@shate-m.by') RETURNING SUPPLIER_ID INTO v_sup_shate;
    INSERT INTO SUPPLIERS (COMPANY_NAME, PHONE, EMAIL) VALUES ('Монлибон', '+375447778899', 'order@monlibon.by') RETURNING SUPPLIER_ID INTO v_sup_mon;

    -- 5. ТОВАРЫ (ИНСЕРТЫ)
    -- Масла
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Shell Helix Ultra 5W-40 4L', v_cat_oil, v_sup_arm, 145.00, 50, 'Синтетическое масло');
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Mobil 1 ESP 5W-30 4L', v_cat_oil, v_sup_shate, 185.00, 30, 'Премиальное масло');

    -- Тормоза
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Колодки Brembo P85072', v_cat_brake, v_sup_arm, 110.00, 20, 'Передние тормозные колодки');
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Диск тормозной TRW DF4465', v_cat_brake, v_sup_mon, 95.00, 40, 'Вентилируемый диск');

    -- Подвеска
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Амортизатор Kayaba Excel-G', v_cat_susp, v_sup_shate, 160.00, 15, 'Задний амортизатор');
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Рычаг Lemforder 35478', v_cat_susp, v_sup_arm, 220.00, 10, 'Передний левый рычаг');

    -- Фильтры
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Фильтр масляный MANN W712', v_cat_filter, v_sup_mon, 25.00, 100, 'Для моторов VAG');
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Фильтр воздушный Bosch', v_cat_filter, v_sup_shate, 35.00, 80, 'Угольный фильтр');

    -- Двигатель
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Свеча зажигания NGK BKR6', v_cat_engine, v_sup_arm, 15.00, 200, 'Никелевая свеча');
    INSERT INTO PRODUCTS (NAME, CATEGORY_ID, SUPPLIER_ID, PRICE, QUANTITY_IN_STOCK, DESCRIPTION)
    VALUES ('Ремень ГРМ Gates', v_cat_engine, v_sup_mon, 75.00, 25, 'Усиленный ремень');

    -- 6. КЛИЕНТЫ (с использованием API для хеширования)
    INSERT INTO USERS (USERNAME, PASSWORD_HASH, ROLE, EMAIL, FIRST_NAME, LAST_NAME, PHONE)
    VALUES ('dmitry_ivanov', AUTOPARTS_UTIL.HASH_PASS('pass123'), 'user', 'ivanov@mail.ru', 'Дмитрий', 'Иванов', '+375291001010')
    RETURNING USER_ID INTO v_user_id;
    INSERT INTO SHOPPING_CARTS (USER_ID) VALUES (v_user_id);

    INSERT INTO USERS (USERNAME, PASSWORD_HASH, ROLE, EMAIL, FIRST_NAME, LAST_NAME, PHONE)
    VALUES ('elena_p', AUTOPARTS_UTIL.HASH_PASS('secret'), 'user', 'elena@gmail.com', 'Елена', 'Петрова', '+375332003040')
    RETURNING USER_ID INTO v_user_id;
    INSERT INTO SHOPPING_CARTS (USER_ID) VALUES (v_user_id);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('База наполнена: 5 категорий, 3 поставщика, 10 товаров, 2 клиента.');
END;
/

-- Процедура для генерации реалистичных заказов
CREATE OR REPLACE PROCEDURE GENERATE_ORDERS_HISTORY(
    p_count IN NUMBER DEFAULT 100000
) IS
    -- Массивы для хранения ID
    TYPE t_ids IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    v_user_ids    t_ids;
    v_product_ids t_ids;
    
    -- Массивы данных
    TYPE t_addresses IS TABLE OF VARCHAR2(255) INDEX BY PLS_INTEGER;
    v_addresses t_addresses;
    
    -- Переменные
    v_order_id    NUMBER;
    v_random_prod NUMBER;
    v_random_qty  NUMBER;
    v_price       NUMBER;
    v_target_user NUMBER;
    v_order_total NUMBER;
    v_order_date  DATE;
    v_delivery_date DATE;
    v_address     VARCHAR2(255);
    v_status      VARCHAR2(20);
    
    v_committed   NUMBER := 0;
BEGIN
    -- Инициализация массивов адресов (реалистичные адреса)
    v_addresses(1) := 'Минск, ул. Ленина, 15-25';
    v_addresses(2) := 'Минск, пр. Независимости, 45-12';
    v_addresses(3) := 'Минск, ул. Немига, 3-18';
    v_addresses(4) := 'Минск, ул. Орловская, 78-5';
    v_addresses(5) := 'Минск, ул. Кальварийская, 41-9';
    v_addresses(6) := 'Брест, ул. Московская, 210-3';
    v_addresses(7) := 'Гродно, ул. Советская, 8-15';
    v_addresses(8) := 'Гомель, пр. Ленина, 10-7';
    v_addresses(9) := 'Витебск, ул. Пушкина, 12-4';
    v_addresses(10):= 'Могилев, ул. Ленинская, 33-11';

    -- 1. Собираем ID активных пользователей-клиентов
    FOR r IN (
        SELECT USER_ID FROM USERS 
        WHERE ROLE = 'user' 
          AND IS_ACTIVE = 'Y' 
          AND IS_BLOCKED = 'N'
    ) LOOP
        v_user_ids(v_user_ids.COUNT + 1) := r.USER_ID;
    END LOOP;

    -- 2. Собираем ID активных товаров в наличии
    FOR r IN (
        SELECT p.PRODUCT_ID 
        FROM PRODUCTS p
        JOIN CATEGORIES c ON p.CATEGORY_ID = c.CATEGORY_ID AND c.IS_ACTIVE = 'Y'
        JOIN SUPPLIERS s ON p.SUPPLIER_ID = s.SUPPLIER_ID AND s.IS_ACTIVE = 'Y'
        WHERE p.IS_ACTIVE = 'Y' 
          AND p.QUANTITY_IN_STOCK > 0
    ) LOOP
        v_product_ids(v_product_ids.COUNT + 1) := r.PRODUCT_ID;
    END LOOP;

    -- Проверка данных
    IF v_user_ids.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Нет активных пользователей для генерации заказов');
    END IF;
    
    IF v_product_ids.COUNT = 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Нет активных товаров для генерации заказов');
    END IF;

    DBMS_OUTPUT.PUT_LINE('Начинаю генерацию ' || p_count || ' заказов...');
    DBMS_OUTPUT.PUT_LINE('Активных пользователей: ' || v_user_ids.COUNT);
    DBMS_OUTPUT.PUT_LINE('Активных товаров: ' || v_product_ids.COUNT);

    -- 3. Цикл генерации реалистичных заказов
    FOR i IN 1..p_count LOOP
        -- Выбираем случайного пользователя
        v_target_user := v_user_ids(TRUNC(DBMS_RANDOM.VALUE(1, v_user_ids.COUNT + 1)));
        
        -- Генерируем реалистичные даты (последние 2 года)
        v_order_date := SYSDATE - DBMS_RANDOM.VALUE(0, 730); -- 2 года назад
        v_delivery_date := v_order_date + DBMS_RANDOM.VALUE(1, 7); -- Доставка через 1-7 дней
        
        -- Выбираем случайный адрес
        v_address := v_addresses(TRUNC(DBMS_RANDOM.VALUE(1, v_addresses.COUNT + 1)));
        
        -- Генерируем статус
        v_status := CASE 
            WHEN DBMS_RANDOM.VALUE < 0.8 THEN 'Completed'      -- 80%
            WHEN DBMS_RANDOM.VALUE < 0.9 THEN 'Processing'    -- 10%
            WHEN DBMS_RANDOM.VALUE < 0.95 THEN 'Shipped'      -- 5%
            ELSE 'Cancelled'                                  -- 5%
        END;
        
        v_order_total := 0;

        -- Создаем заголовок заказа (ВСЕГДА с датой доставки!)
        INSERT INTO ORDERS (
            USER_ID, 
            STATUS, 
            ORDER_DATE, 
            SHIPPING_ADDRESS,
            DELIVERY_DATE,
            TOTAL_AMOUNT
        ) VALUES (
            v_target_user, 
            v_status,
            v_order_date,
            v_address,
            v_delivery_date, -- ВСЕГДА заполняем дату доставки
            0  -- Временно 0, посчитаем ниже
        ) RETURNING ORDER_ID INTO v_order_id;

        -- Для каждого заказа создаем от 1 до 4 позиций
        FOR j IN 1..TRUNC(DBMS_RANDOM.VALUE(1, 5)) LOOP
            v_random_prod := v_product_ids(TRUNC(DBMS_RANDOM.VALUE(1, v_product_ids.COUNT + 1)));
            v_random_qty  := TRUNC(DBMS_RANDOM.VALUE(1, 5));
            
            -- Получаем цену товара (историческую цену)
            BEGIN
                SELECT PRICE * (1 - DBMS_RANDOM.VALUE(0, 0.3)) -- Скидка 0-30% для реализма
                INTO v_price 
                FROM PRODUCTS 
                WHERE PRODUCT_ID = v_random_prod;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    CONTINUE; -- Пропускаем если товар вдруг не найден
            END;

            -- Добавляем позицию заказа
            INSERT INTO ORDER_ITEMS (ORDER_ID, PRODUCT_ID, QUANTITY, PRICE_AT_PURCHASE)
            VALUES (v_order_id, v_random_prod, v_random_qty, v_price);
            
            v_order_total := v_order_total + (v_price * v_random_qty);
        END LOOP;
        
        -- Обновляем сумму заказа только если есть товары
        IF v_order_total > 0 THEN
            UPDATE ORDERS 
            SET TOTAL_AMOUNT = v_order_total 
            WHERE ORDER_ID = v_order_id;
        ELSE
            -- Если нет товаров, отменяем заказ
            UPDATE ORDERS 
            SET STATUS = 'Cancelled', 
                TOTAL_AMOUNT = 0 
            WHERE ORDER_ID = v_order_id;
        END IF;

        -- Коммитим каждые 1000 записей
        IF MOD(i, 1000) = 0 THEN
            COMMIT;
            v_committed := v_committed + 1000;
            DBMS_OUTPUT.PUT_LINE('Создано ' || v_committed || ' заказов...');
            
            -- Периодическая статистика
            IF MOD(v_committed, 10000) = 0 THEN
                DBMS_OUTPUT.PUT_LINE('Текущий прогресс: ' || 
                    ROUND(v_committed * 100 / p_count, 1) || '%');
            END IF;
        END IF;
    END LOOP;

    COMMIT;
    
    -- Итоговая статистика
    DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Генерация ' || p_count || ' заказов завершена.');
    
    FOR r IN (
        SELECT STATUS, COUNT(*) as cnt
        FROM ORDERS 
        GROUP BY STATUS
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('Статус ' || r.STATUS || ': ' || r.cnt || ' заказов');
    END LOOP;
    
    -- Проверка, что все заказы имеют DELIVERY_DATE
    DECLARE
        v_null_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_null_count 
        FROM ORDERS 
        WHERE DELIVERY_DATE IS NULL;
        
        IF v_null_count > 0 THEN
            DBMS_OUTPUT.PUT_LINE('ВНИМАНИЕ: ' || v_null_count || ' заказов без даты доставки!');
        ELSE
            DBMS_OUTPUT.PUT_LINE('✓ Все заказы имеют дату доставки');
        END IF;
    END;
    
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Ошибка при генерации заказов: ' || SQLERRM);
        RAISE;
END GENERATE_ORDERS_HISTORY;
/

BEGIN
    GENERATE_ORDERS_HISTORY(100000); -- 100к заказов
END;
/
SELECT * FROM orders;

DELETE FROM ORDERS WHERE ORDER_DATE < TO_DATE('2100-01-01', 'YYYY-MM-DD')