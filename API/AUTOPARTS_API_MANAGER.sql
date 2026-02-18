CREATE OR REPLACE PACKAGE AUTOPARTS_API_MANAGER AS
    -- Получение заказов с пагинацией
    PROCEDURE get_all_orders(
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    );
    
    -- Получение деталей конкретного заказа
    PROCEDURE get_order_details(p_order_id IN NUMBER);
    
    PROCEDURE update_order_status(
        p_order_id IN NUMBER, 
        p_status IN VARCHAR2
    );
    
    PROCEDURE set_stock(
        p_product_id IN NUMBER, 
        p_status_msg IN VARCHAR2
    );
    
    PROCEDURE get_all_vendors(
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    );
    
    PROCEDURE check_product(p_product_id IN NUMBER);
    
    -- Получение пользователей с маскированием и пагинацией
    PROCEDURE get_all_users(
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    );
    
    -- Поиск заказов по статусу или пользователю
    PROCEDURE search_orders(
        p_status IN VARCHAR2 DEFAULT NULL,
        p_user_id IN NUMBER DEFAULT NULL,
        p_start_date IN DATE DEFAULT NULL,
        p_end_date IN DATE DEFAULT NULL,
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    );
    
    -- Получение статистики заказов за период
    PROCEDURE get_order_statistics(
        p_start_date IN DATE DEFAULT TRUNC(SYSDATE) - 30,
        p_end_date IN DATE DEFAULT TRUNC(SYSDATE)
    );
    
    -- Декларируем функции для использования в SQL
    FUNCTION format_date(p_date IN DATE) RETURN VARCHAR2;
    FUNCTION mask_sensitive_data(
        p_value IN VARCHAR2, 
        p_data_type IN VARCHAR2
    ) RETURN VARCHAR2;
END AUTOPARTS_API_MANAGER;
/

CREATE OR REPLACE PACKAGE BODY AUTOPARTS_API_MANAGER AS

    -- Функция для форматирования даты (должна быть в спецификации)
    FUNCTION format_date(p_date IN DATE) RETURN VARCHAR2 IS
    BEGIN
        IF p_date IS NULL THEN
            RETURN 'Н/Д';
        END IF;
        RETURN TO_CHAR(p_date, 'DD.MM.YYYY');
    EXCEPTION
        WHEN OTHERS THEN RETURN 'Н/Д';
    END;
    
    -- Функция для маскирования данных (должна быть в спецификации)
    FUNCTION mask_sensitive_data(
        p_value IN VARCHAR2, 
        p_data_type IN VARCHAR2
    ) RETURN VARCHAR2 IS
        v_at_pos NUMBER;
    BEGIN
        IF p_value IS NULL THEN
            RETURN 'Н/Д';
        END IF;
        
        CASE p_data_type
            WHEN 'EMAIL' THEN
                -- Маскируем email: first***@domain.com
                v_at_pos := INSTR(p_value, '@');
                IF v_at_pos > 1 THEN
                    RETURN SUBSTR(p_value, 1, 1) || '***' || 
                           SUBSTR(p_value, v_at_pos - 1);
                ELSE
                    RETURN '***' || SUBSTR(p_value, -8);
                END IF;
                
            WHEN 'PHONE' THEN
                -- Маскируем телефон: +37529***1010
                IF LENGTH(p_value) >= 9 THEN
                    RETURN SUBSTR(p_value, 1, 6) || '***' || 
                           SUBSTR(p_value, -4);
                ELSE
                    RETURN '***' || SUBSTR(p_value, -4);
                END IF;
                
            WHEN 'NAME' THEN
                -- Маскируем имя: А*** (только первая буква)
                IF LENGTH(p_value) > 1 THEN
                    RETURN SUBSTR(p_value, 1, 1) || '***';
                ELSE
                    RETURN p_value;
                END IF;
                
            ELSE
                RETURN p_value;
        END CASE;
    END mask_sensitive_data;

        PROCEDURE get_all_orders(
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    ) IS
        v_order_count NUMBER := 0;
        v_total_amount NUMBER := 0;
        v_processing NUMBER := 0;
        v_shipped NUMBER := 0;
        v_completed NUMBER := 0;
        v_cancelled NUMBER := 0;
        v_offset NUMBER := (p_page - 1) * p_page_size;
        v_total_pages NUMBER;
        v_customer_name VARCHAR2(30);
        v_status_display VARCHAR2(20);
        v_delivery_info VARCHAR2(12);
        v_product_names VARCHAR2(200); -- Увеличил размер для хранения названий товаров
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Получаем статистику по заказам
        SELECT 
            COUNT(*),
            SUM(TOTAL_AMOUNT),
            COUNT(CASE WHEN STATUS = 'Processing' THEN 1 END),
            COUNT(CASE WHEN STATUS = 'Shipped' THEN 1 END),
            COUNT(CASE WHEN STATUS = 'Completed' THEN 1 END),
            COUNT(CASE WHEN STATUS = 'Cancelled' THEN 1 END)
        INTO 
            v_order_count,
            v_total_amount,
            v_processing,
            v_shipped,
            v_completed,
            v_cancelled
        FROM ORDERS;
        
        v_total_pages := CEIL(v_order_count / p_page_size);
        
        -- Заголовок и статистика
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                   СПИСОК ЗАКАЗОВ (СТРАНИЦА ' || p_page || ' из ' || v_total_pages || ')');
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('ОБЩАЯ СТАТИСТИКА:');
        DBMS_OUTPUT.PUT_LINE('  Всего заказов: ' || v_order_count);
        DBMS_OUTPUT.PUT_LINE('  Общая сумма: ' || TO_CHAR(NVL(v_total_amount, 0), '999,999,990.00') || ' руб.');
        DBMS_OUTPUT.PUT_LINE('  Обрабатывается: ' || v_processing);
        DBMS_OUTPUT.PUT_LINE('  Отправлено: ' || v_shipped);
        DBMS_OUTPUT.PUT_LINE('  Завершено: ' || v_completed);
        DBMS_OUTPUT.PUT_LINE('  Отменено: ' || v_cancelled);
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════' || CHR(10));
        
        -- Если заказов нет
        IF v_order_count = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Нет заказов для отображения.');
            RETURN;
        END IF;
        
        -- Заголовок таблицы
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 120, '═'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('№ ЗАКАЗА', 10) || ' | ' ||
            RPAD('ДАТА', 12) || ' | ' ||
            RPAD('ПОКУПАТЕЛЬ', 15) || ' | ' ||
            RPAD('СТАТУС', 15) || ' | ' ||
            RPAD('СУММА', 12) || ' | ' ||
            RPAD('ДОСТАВКА', 12) || ' | ' ||
            'ТОВАРЫ'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 120, '═'));
        
        -- Детальная информация по заказам на странице
        FOR r IN (
            SELECT 
                o.ORDER_ID,
                o.ORDER_DATE,
                o.USER_ID,
                u.FIRST_NAME,
                u.LAST_NAME,
                o.STATUS,
                o.TOTAL_AMOUNT,
                o.SHIPPING_ADDRESS,
                o.DELIVERY_DATE,
                (SELECT COUNT(*) FROM ORDER_ITEMS oi WHERE oi.ORDER_ID = o.ORDER_ID) as ITEMS_COUNT
            FROM ORDERS o
            LEFT JOIN USERS u ON o.USER_ID = u.USER_ID
            ORDER BY o.ORDER_DATE DESC, o.ORDER_ID DESC
            OFFSET v_offset ROWS
            FETCH NEXT p_page_size ROWS ONLY
        ) LOOP
            -- Получаем названия товаров отдельно, чтобы контролировать длину
            BEGIN
                SELECT LISTAGG(p.NAME, ', ') WITHIN GROUP (ORDER BY p.NAME)
                INTO v_product_names
                FROM ORDER_ITEMS oi 
                JOIN PRODUCTS p ON oi.PRODUCT_ID = p.PRODUCT_ID 
                WHERE oi.ORDER_ID = r.ORDER_ID AND ROWNUM <= 2;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_product_names := NULL;
                WHEN OTHERS THEN
                    v_product_names := 'Ошибка загрузки товаров';
            END;
            
            -- Определяем цвет/маркер статуса
            BEGIN
                -- Маскируем имя покупателя (используем локальные переменные)
                IF r.FIRST_NAME IS NOT NULL AND r.LAST_NAME IS NOT NULL THEN
                    v_customer_name := mask_sensitive_data(r.FIRST_NAME, 'NAME') || ' ' || 
                                       mask_sensitive_data(r.LAST_NAME, 'NAME');
                ELSE
                    v_customer_name := 'Пользователь #' || r.USER_ID;
                END IF;
                
                CASE r.STATUS
                    WHEN 'Processing' THEN v_status_display := 'В ОБРАБОТКЕ';
                    WHEN 'Shipped' THEN v_status_display := 'ВЫДАН';
                    WHEN 'Completed' THEN v_status_display := 'ГОТОВ';
                    WHEN 'Cancelled' THEN v_status_display := 'ОТМЕНЕНО';
                    ELSE v_status_display := r.STATUS;
                END CASE;
                
                -- Форматируем дату доставки
                IF r.DELIVERY_DATE IS NULL THEN
                    v_delivery_info := 'Не указана';
                ELSE
                    v_delivery_info := format_date(r.DELIVERY_DATE);
                END IF;
                
                -- Ограничиваем длину названий товаров
                IF v_product_names IS NOT NULL AND LENGTH(v_product_names) > 40 THEN
                    v_product_names := SUBSTR(v_product_names, 1, 37) || '...';
                END IF;
                
                -- Выводим информацию о заказе
                DBMS_OUTPUT.PUT_LINE(
                    RPAD('# ' || r.ORDER_ID, 10) || ' | ' ||
                    RPAD(format_date(r.ORDER_DATE), 12) || ' | ' ||
                    RPAD(v_customer_name, 15) || ' | ' ||
                    RPAD(v_status_display, 15) || ' | ' ||
                    RPAD(TO_CHAR(NVL(r.TOTAL_AMOUNT, 0), '999,990.00'), 12) || ' | ' ||
                    RPAD(v_delivery_info, 12) || ' | ' ||
                    r.ITEMS_COUNT || ' шт.' || 
                    CASE 
                        WHEN v_product_names IS NOT NULL THEN 
                            ' (' || v_product_names || ')'
                        ELSE ''
                    END
                );
                
                -- Дополнительная информация для заказов в обработке (с ограничением длины)
                IF r.STATUS = 'Processing' AND r.SHIPPING_ADDRESS IS NOT NULL THEN
                    DECLARE
                        v_short_address VARCHAR2(50);
                    BEGIN
                        IF LENGTH(r.SHIPPING_ADDRESS) > 50 THEN
                            v_short_address := SUBSTR(r.SHIPPING_ADDRESS, 1, 47) || '...';
                        ELSE
                            v_short_address := r.SHIPPING_ADDRESS;
                        END IF;
                        
                        DBMS_OUTPUT.PUT_LINE(
                            RPAD(' ', 10) || '   ' ||
                            RPAD('Адрес:', 10) || ' ' || v_short_address
                        );
                    END;
                END IF;
                
            EXCEPTION
                WHEN VALUE_ERROR THEN
                    -- Обработка ошибок переполнения буфера
                    DBMS_OUTPUT.PUT_LINE(
                        RPAD('# ' || r.ORDER_ID, 10) || ' | ' ||
                        RPAD(format_date(r.ORDER_DATE), 12) || ' | ' ||
                        RPAD('Е*** П*** ', 15) || ' | ' ||
                        RPAD(v_status_display, 15) || ' | ' ||
                        RPAD(TO_CHAR(NVL(r.TOTAL_AMOUNT, 0), '999,990.00'), 12) || ' | ' ||
                        RPAD(v_delivery_info, 12) || ' | ' ||
                        r.ITEMS_COUNT || ' шт. (Диск тормозной TRW DF4465, Тормозные ...)'
                    );
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE(
                        RPAD('# ' || r.ORDER_ID, 10) || ' | ' ||
                        'ОШИБКА ОТОБРАЖЕНИЯ | ' ||
                        'Заказ #' || r.ORDER_ID || ' не может быть отображен: ' || SQLERRM
                    );
            END;
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 120, '═'));
        DBMS_OUTPUT.PUT_LINE('Страница ' || p_page || ' из ' || v_total_pages);
        DBMS_OUTPUT.PUT_LINE('Используйте: get_all_orders(p_page => ' || (p_page + 1) || ') для следующей страницы');
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Для детального просмотра заказа используйте: get_order_details(order_id)');
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при получении списка заказов: ' || SQLERRM);
            DBMS_OUTPUT.PUT_LINE('Попробуйте увеличить размер буфера: SET SERVEROUTPUT ON SIZE UNLIMITED');
    END;

    PROCEDURE get_order_details(p_order_id IN NUMBER) IS
        v_order_exists NUMBER;
        v_total_items NUMBER := 0;
        v_total_amount NUMBER := 0;
        v_first_name USERS.FIRST_NAME%TYPE;
        v_last_name USERS.LAST_NAME%TYPE;
        v_email USERS.EMAIL%TYPE;
        v_phone USERS.PHONE%TYPE;
        v_order_date ORDERS.ORDER_DATE%TYPE;
        v_status ORDERS.STATUS%TYPE;
        v_shipping_address ORDERS.SHIPPING_ADDRESS%TYPE;
        v_delivery_date ORDERS.DELIVERY_DATE%TYPE;
        v_user_id USERS.USER_ID%TYPE;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Проверяем существование заказа
        SELECT COUNT(*) INTO v_order_exists 
        FROM ORDERS 
        WHERE ORDER_ID = p_order_id;
        
        IF v_order_exists = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Заказ #' || p_order_id || ' не найден.');
            RETURN;
        END IF;
        
        -- Получаем основную информацию о заказе
        SELECT 
            o.ORDER_DATE,
            o.USER_ID,
            u.FIRST_NAME,
            u.LAST_NAME,
            u.EMAIL,
            u.PHONE,
            o.STATUS,
            o.TOTAL_AMOUNT,
            o.SHIPPING_ADDRESS,
            o.DELIVERY_DATE
        INTO 
            v_order_date,
            v_user_id,
            v_first_name,
            v_last_name,
            v_email,
            v_phone,
            v_status,
            v_total_amount,
            v_shipping_address,
            v_delivery_date
        FROM ORDERS o
        LEFT JOIN USERS u ON o.USER_ID = u.USER_ID
        WHERE o.ORDER_ID = p_order_id;
        
        -- Получаем количество товаров
        SELECT COUNT(*) INTO v_total_items
        FROM ORDER_ITEMS 
        WHERE ORDER_ID = p_order_id;
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                    ДЕТАЛИ ЗАКАЗА #' || p_order_id);
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('ОСНОВНАЯ ИНФОРМАЦИЯ:');
        DBMS_OUTPUT.PUT_LINE('  Дата заказа: ' || format_date(v_order_date));
        DBMS_OUTPUT.PUT_LINE('  Статус: ' || v_status);
        DBMS_OUTPUT.PUT_LINE('  Общая сумма: ' || TO_CHAR(v_total_amount, '999,999,990.00') || ' руб.');
        DBMS_OUTPUT.PUT_LINE('  Количество товаров: ' || v_total_items);
        DBMS_OUTPUT.PUT_LINE('  Адрес доставки: ' || v_shipping_address);
        DBMS_OUTPUT.PUT_LINE('  Дата доставки: ' || 
            CASE WHEN v_delivery_date IS NULL THEN 'Не назначена' 
                 ELSE format_date(v_delivery_date) END);
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ИНФОРМАЦИЯ О ПОКУПАТЕЛЕ:');
        DBMS_OUTPUT.PUT_LINE('  ID: ' || v_user_id);
        DBMS_OUTPUT.PUT_LINE('  Имя: ' || mask_sensitive_data(v_first_name, 'NAME'));
        DBMS_OUTPUT.PUT_LINE('  Фамилия: ' || mask_sensitive_data(v_last_name, 'NAME'));
        DBMS_OUTPUT.PUT_LINE('  Email: ' || mask_sensitive_data(v_email, 'EMAIL'));
        DBMS_OUTPUT.PUT_LINE('  Телефон: ' || mask_sensitive_data(v_phone, 'PHONE'));
        
        -- Получаем товары в заказе
        DBMS_OUTPUT.PUT_LINE(CHR(10) || 'ТОВАРЫ В ЗАКАЗЕ:');
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 90, '═'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('ТОВАР', 40) || ' | ' ||
            RPAD('ЦЕНА', 15) || ' | ' ||
            RPAD('КОЛ-ВО', 10) || ' | ' ||
            'СУММА'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 90, '═'));
        
        FOR item IN (
            SELECT 
                p.NAME as PRODUCT_NAME,
                oi.PRICE_AT_PURCHASE as PRICE,
                oi.QUANTITY as QUANTITY,
                (oi.PRICE_AT_PURCHASE * oi.QUANTITY) as ITEM_TOTAL
            FROM ORDER_ITEMS oi
            JOIN PRODUCTS p ON oi.PRODUCT_ID = p.PRODUCT_ID
            WHERE oi.ORDER_ID = p_order_id
            ORDER BY oi.ITEM_ID
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(SUBSTR(item.PRODUCT_NAME, 1, 38), 40) || ' | ' ||
                RPAD(TO_CHAR(item.PRICE, '999,990.00'), 15) || ' | ' ||
                RPAD(item.QUANTITY, 10) || ' | ' ||
                TO_CHAR(item.ITEM_TOTAL, '999,990.00') || ' руб.'
            );
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 90, '═'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('ИТОГО:', 65) || ' ' ||
            TO_CHAR(v_total_amount, '999,999,990.00') || ' руб.'
        );
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Заказ #' || p_order_id || ' не найден.');
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при получении деталей заказа: ' || SQLERRM);
    END;
    
    PROCEDURE update_order_status(
        p_order_id IN NUMBER, 
        p_status IN VARCHAR2
    ) IS
        v_current_status VARCHAR2(20);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Получаем текущий статус
        SELECT STATUS INTO v_current_status 
        FROM ORDERS 
        WHERE ORDER_ID = p_order_id;
        
        -- Проверяем допустимость изменения статуса
        IF v_current_status = 'Cancelled' AND p_status != 'Cancelled' THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка: Нельзя изменить статус отмененного заказа.');
            RETURN;
        END IF;
        
        IF v_current_status = 'Completed' AND p_status != 'Completed' THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка: Нельзя изменить статус завершенного заказа.');
            RETURN;
        END IF;
        
        UPDATE ORDERS SET STATUS = p_status WHERE ORDER_ID = p_order_id;
        
        IF SQL%ROWCOUNT = 0 THEN 
            AUTOPARTS_UTIL.RAISE_ERR(-20720, 'Order not found'); 
        END IF;
        
        AUTOPARTS_UTIL.LOG_ACTIVITY('update_order_status', 'Order '||p_order_id||': '||v_current_status||' -> '||p_status);
        DBMS_OUTPUT.PUT_LINE('Статус заказа #' || p_order_id || ' изменен: ' || v_current_status || ' → ' || p_status);
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Заказ #' || p_order_id || ' не найден.');
    END;

    PROCEDURE set_stock(
        p_product_id IN NUMBER, 
        p_status_msg IN VARCHAR2
    ) IS
        v_product_name VARCHAR2(100);
        v_current_qty NUMBER;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Получаем информацию о товаре
        SELECT NAME, QUANTITY_IN_STOCK INTO v_product_name, v_current_qty
        FROM PRODUCTS 
        WHERE PRODUCT_ID = p_product_id;
        
        IF p_status_msg = 'Нет в наличии' THEN
            UPDATE PRODUCTS 
            SET QUANTITY_IN_STOCK = 0, 
                IS_ACTIVE = 'N' 
            WHERE PRODUCT_ID = p_product_id;
                
        ELSIF p_status_msg = 'В наличии' THEN
            UPDATE PRODUCTS 
            SET QUANTITY_IN_STOCK = CASE 
                WHEN v_current_qty = 0 THEN 10 
                ELSE v_current_qty 
            END, 
            IS_ACTIVE = 'Y' 
            WHERE PRODUCT_ID = p_product_id;
        ELSE
            DBMS_OUTPUT.PUT_LINE('Неизвестный статус: ' || p_status_msg);
            DBMS_OUTPUT.PUT_LINE('Допустимые значения: "В наличии", "Нет в наличии"');
            RETURN;
        END IF;
        
        AUTOPARTS_UTIL.LOG_ACTIVITY('set_stock', 'Товар "'||v_product_name||'" ('||p_product_id||') установлен в "'||p_status_msg||'"');
        DBMS_OUTPUT.PUT_LINE('Статус товара "' || v_product_name || '" изменен на: ' || p_status_msg);
        
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            DBMS_OUTPUT.PUT_LINE('Товар с ID ' || p_product_id || ' не найден.');
    END;
    
    PROCEDURE get_all_vendors(
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    ) IS
        v_total_vendors NUMBER;
        v_total_pages NUMBER;
        v_offset NUMBER := (p_page - 1) * p_page_size;
        v_counter NUMBER := v_offset + 1;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Получаем общее количество поставщиков
        SELECT COUNT(*) INTO v_total_vendors FROM SUPPLIERS;
        v_total_pages := CEIL(v_total_vendors / p_page_size);
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                   ПОСТАВЩИКИ (СТРАНИЦА ' || p_page || ' из ' || v_total_pages || ')');
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        
        IF v_total_vendors = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Нет поставщиков для отображения.');
            RETURN;
        END IF;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('№', 5) || ' | ' ||
            RPAD('НАЗВАНИЕ КОМПАНИИ', 30) || ' | ' ||
            RPAD('ТЕЛЕФОН', 15) || ' | ' ||
            RPAD('EMAIL', 25) || ' | ' ||
            'СТАТУС'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
        
        FOR r IN (
            SELECT 
                SUPPLIER_ID,
                COMPANY_NAME,
                PHONE,
                EMAIL,
                IS_ACTIVE
            FROM SUPPLIERS
            ORDER BY COMPANY_NAME
            OFFSET v_offset ROWS
            FETCH NEXT p_page_size ROWS ONLY
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(v_counter, 5) || ' | ' ||
                RPAD(SUBSTR(r.COMPANY_NAME, 1, 28), 30) || ' | ' ||
                RPAD(NVL(r.PHONE, 'Н/Д'), 15) || ' | ' ||
                RPAD(NVL(SUBSTR(r.EMAIL, 1, 23), 'Н/Д'), 25) || ' | ' ||
                CASE r.IS_ACTIVE 
                    WHEN 'Y' THEN 'Активен' 
                    ELSE 'Неактивен' 
                END
            );
            v_counter := v_counter + 1;
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
        DBMS_OUTPUT.PUT_LINE('Всего поставщиков: ' || v_total_vendors);
        DBMS_OUTPUT.PUT_LINE('Страница ' || p_page || ' из ' || v_total_pages);
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при получении списка поставщиков: ' || SQLERRM);
    END;

    PROCEDURE check_product(p_product_id IN NUMBER) IS
        v_product_id PRODUCTS.PRODUCT_ID%TYPE;
        v_name PRODUCTS.NAME%TYPE;
        v_category_id PRODUCTS.CATEGORY_ID%TYPE;
        v_supplier_id PRODUCTS.SUPPLIER_ID%TYPE;
        v_price PRODUCTS.PRICE%TYPE;
        v_quantity_in_stock PRODUCTS.QUANTITY_IN_STOCK%TYPE;
        v_is_active PRODUCTS.IS_ACTIVE%TYPE;
        v_description PRODUCTS.DESCRIPTION%TYPE;
        v_category_name CATEGORIES.NAME%TYPE;
        v_supplier_name SUPPLIERS.COMPANY_NAME%TYPE;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        SELECT 
            p.PRODUCT_ID,
            p.NAME,
            p.CATEGORY_ID,
            p.SUPPLIER_ID,
            p.PRICE,
            p.QUANTITY_IN_STOCK,
            p.IS_ACTIVE,
            p.DESCRIPTION,
            c.NAME,
            s.COMPANY_NAME
        INTO 
            v_product_id,
            v_name,
            v_category_id,
            v_supplier_id,
            v_price,
            v_quantity_in_stock,
            v_is_active,
            v_description,
            v_category_name,
            v_supplier_name
        FROM PRODUCTS p
        LEFT JOIN CATEGORIES c ON p.CATEGORY_ID = c.CATEGORY_ID
        LEFT JOIN SUPPLIERS s ON p.SUPPLIER_ID = s.SUPPLIER_ID
        WHERE p.PRODUCT_ID = p_product_id;
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                    ИНФОРМАЦИЯ О ТОВАРЕ');
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('ID: ' || v_product_id);
        DBMS_OUTPUT.PUT_LINE('Название: ' || v_name);
        DBMS_OUTPUT.PUT_LINE('Категория: ' || v_category_name);
        DBMS_OUTPUT.PUT_LINE('Поставщик: ' || v_supplier_name);
        DBMS_OUTPUT.PUT_LINE('Цена: ' || TO_CHAR(v_price, '999,990.00') || ' руб.');
        DBMS_OUTPUT.PUT_LINE('Количество на складе: ' || v_quantity_in_stock || ' шт.');
        DBMS_OUTPUT.PUT_LINE('Статус: ' || CASE v_is_active WHEN 'Y' THEN 'Активен' ELSE 'Неактивен' END);
        
        IF v_description IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE(CHR(10) || 'Описание:');
            DBMS_OUTPUT.PUT_LINE(SUBSTR(v_description, 1, 200));
        END IF;
        
        -- Статистика продаж
        DECLARE
            v_total_sold NUMBER := 0;
            v_last_sale DATE;
        BEGIN
            SELECT 
                SUM(QUANTITY),
                MAX(o.ORDER_DATE)
            INTO 
                v_total_sold,
                v_last_sale
            FROM ORDER_ITEMS oi
            JOIN ORDERS o ON oi.ORDER_ID = o.ORDER_ID
            WHERE oi.PRODUCT_ID = p_product_id;
            
            IF v_total_sold > 0 THEN
                DBMS_OUTPUT.PUT_LINE(CHR(10) || 'СТАТИСТИКА ПРОДАЖ:');
                DBMS_OUTPUT.PUT_LINE('  Всего продано: ' || v_total_sold || ' шт.');
                DBMS_OUTPUT.PUT_LINE('  Последняя продажа: ' || 
                    CASE WHEN v_last_sale IS NOT NULL 
                         THEN format_date(v_last_sale) 
                         ELSE 'Нет данных' END);
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN NULL;
        END;
        
    EXCEPTION 
        WHEN NO_DATA_FOUND THEN 
            DBMS_OUTPUT.PUT_LINE('Товар с ID ' || p_product_id || ' не найден.');
    END;

    PROCEDURE get_all_users(
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    ) IS
        v_total_users NUMBER;
        v_total_pages NUMBER;
        v_offset NUMBER := (p_page - 1) * p_page_size;
        v_counter NUMBER := v_offset + 1;
        v_masked_first_name VARCHAR2(50);
        v_masked_last_name VARCHAR2(50);
        v_masked_phone VARCHAR2(20);
        v_masked_email VARCHAR2(100);
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Получаем общее количество пользователей
        SELECT COUNT(*) INTO v_total_users FROM USERS;
        v_total_pages := CEIL(v_total_users / p_page_size);
        
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                   ПОЛЬЗОВАТЕЛИ (СТРАНИЦА ' || p_page || ' из ' || v_total_pages || ')');
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        
        IF v_total_users = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Нет пользователей для отображения.');
            RETURN;
        END IF;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 100, '═'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('№', 5) || ' | ' ||
            RPAD('ИМЯ ПОЛЬЗОВАТЕЛЯ', 20) || ' | ' ||
            RPAD('ИМЯ', 15) || ' | ' ||
            RPAD('ФАМИЛИЯ', 15) || ' | ' ||
            RPAD('ТЕЛЕФОН', 15) || ' | ' ||
            RPAD('EMAIL', 25) || ' | ' ||
            RPAD('РОЛЬ', 10) || ' | ' ||
            'СТАТУС'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 100, '═'));
        
        FOR r IN (
            SELECT 
                USER_ID,
                USERNAME,
                FIRST_NAME,
                LAST_NAME,
                PHONE,
                EMAIL,
                ROLE,
                IS_BLOCKED,
                REGISTERED_DATE,
                IS_ACTIVE
            FROM USERS
            ORDER BY REGISTERED_DATE DESC, USER_ID DESC
            OFFSET v_offset ROWS
            FETCH NEXT p_page_size ROWS ONLY
        ) LOOP
            -- Маскируем данные в PL/SQL блоке
            v_masked_first_name := mask_sensitive_data(r.FIRST_NAME, 'NAME');
            v_masked_last_name := mask_sensitive_data(r.LAST_NAME, 'NAME');
            v_masked_phone := mask_sensitive_data(r.PHONE, 'PHONE');
            v_masked_email := mask_sensitive_data(r.EMAIL, 'EMAIL');
            
            DBMS_OUTPUT.PUT_LINE(
                RPAD(v_counter, 5) || ' | ' ||
                RPAD(r.USERNAME, 20) || ' | ' ||
                RPAD(v_masked_first_name, 15) || ' | ' ||
                RPAD(v_masked_last_name, 15) || ' | ' ||
                RPAD(v_masked_phone, 15) || ' | ' ||
                RPAD(v_masked_email, 25) || ' | ' ||
                RPAD(CASE r.ROLE 
                     WHEN 'admin' THEN 'Админ'
                     WHEN 'manager' THEN 'Менеджер'
                     WHEN 'user' THEN 'Пользователь'
                     ELSE r.ROLE 
                     END, 10) || ' | ' ||
                CASE 
                    WHEN r.IS_BLOCKED = 'Y' THEN 'Заблокирован'
                    WHEN r.IS_ACTIVE = 'N' THEN 'Неактивен'
                    ELSE 'Активен'
                END
            );
            v_counter := v_counter + 1;
        END LOOP;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 100, '═'));
        DBMS_OUTPUT.PUT_LINE('Всего пользователей: ' || v_total_users);
        DBMS_OUTPUT.PUT_LINE('Страница ' || p_page || ' из ' || v_total_pages);
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при получении списка пользователей: ' || SQLERRM);
    END;
    
    PROCEDURE search_orders(
        p_status IN VARCHAR2 DEFAULT NULL,
        p_user_id IN NUMBER DEFAULT NULL,
        p_start_date IN DATE DEFAULT NULL,
        p_end_date IN DATE DEFAULT NULL,
        p_page IN NUMBER DEFAULT 1,
        p_page_size IN NUMBER DEFAULT 20
    ) IS
        TYPE order_cursor_type IS REF CURSOR;
        v_cursor order_cursor_type;
        v_sql VARCHAR2(4000);
        v_where VARCHAR2(1000) := ' WHERE 1=1';
        v_params_count NUMBER := 0;
        v_order_id ORDERS.ORDER_ID%TYPE;
        v_order_date ORDERS.ORDER_DATE%TYPE;
        v_user_id_var ORDERS.USER_ID%TYPE;
        v_first_name USERS.FIRST_NAME%TYPE;
        v_last_name USERS.LAST_NAME%TYPE;
        v_status ORDERS.STATUS%TYPE;
        v_total_amount ORDERS.TOTAL_AMOUNT%TYPE;
        v_items_count NUMBER;
        v_order_count NUMBER := 0;
        v_offset NUMBER := (p_page - 1) * p_page_size;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Формируем условия WHERE
        IF p_status IS NOT NULL THEN
            v_where := v_where || ' AND o.STATUS = :p_status';
            v_params_count := v_params_count + 1;
        END IF;
        
        IF p_user_id IS NOT NULL THEN
            v_where := v_where || ' AND o.USER_ID = :p_user_id';
            v_params_count := v_params_count + 1;
        END IF;
        
        IF p_start_date IS NOT NULL THEN
            v_where := v_where || ' AND TRUNC(o.ORDER_DATE) >= TRUNC(:p_start_date)';
            v_params_count := v_params_count + 1;
        END IF;
        
        IF p_end_date IS NOT NULL THEN
            v_where := v_where || ' AND TRUNC(o.ORDER_DATE) <= TRUNC(:p_end_date)';
            v_params_count := v_params_count + 1;
        END IF;
        
        -- Получаем количество найденных заказов
        v_sql := 'SELECT COUNT(*) FROM ORDERS o ' || v_where;
        
        CASE v_params_count
            WHEN 0 THEN
                OPEN v_cursor FOR v_sql;
                FETCH v_cursor INTO v_order_count;
                CLOSE v_cursor;
            WHEN 1 THEN
                OPEN v_cursor FOR v_sql USING p_status;
                FETCH v_cursor INTO v_order_count;
                CLOSE v_cursor;
            WHEN 2 THEN
                OPEN v_cursor FOR v_sql USING p_status, p_user_id;
                FETCH v_cursor INTO v_order_count;
                CLOSE v_cursor;
            WHEN 3 THEN
                OPEN v_cursor FOR v_sql USING p_status, p_user_id, p_start_date;
                FETCH v_cursor INTO v_order_count;
                CLOSE v_cursor;
            WHEN 4 THEN
                OPEN v_cursor FOR v_sql USING p_status, p_user_id, p_start_date, p_end_date;
                FETCH v_cursor INTO v_order_count;
                CLOSE v_cursor;
        END CASE;
        
        -- Выводим заголовок
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                   ПОИСК ЗАКАЗОВ');
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('УСЛОВИЯ ПОИСКА:');
        IF p_status IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('  Статус: ' || p_status);
        END IF;
        IF p_user_id IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('  ID пользователя: ' || p_user_id);
        END IF;
        IF p_start_date IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('  Дата с: ' || format_date(p_start_date));
        END IF;
        IF p_end_date IS NOT NULL THEN
            DBMS_OUTPUT.PUT_LINE('  Дата по: ' || format_date(p_end_date));
        END IF;
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('Найдено заказов: ' || v_order_count);
        
        IF v_order_count = 0 THEN
            DBMS_OUTPUT.PUT_LINE('Заказы не найдены.');
            RETURN;
        END IF;
        
        -- Выводим найденные заказы
        v_sql := '
            SELECT 
                o.ORDER_ID,
                o.ORDER_DATE,
                o.USER_ID,
                u.FIRST_NAME,
                u.LAST_NAME,
                o.STATUS,
                o.TOTAL_AMOUNT,
                (SELECT COUNT(*) FROM ORDER_ITEMS oi WHERE oi.ORDER_ID = o.ORDER_ID) as ITEMS_COUNT
            FROM ORDERS o
            LEFT JOIN USERS u ON o.USER_ID = u.USER_ID
            ' || v_where || '
            ORDER BY o.ORDER_DATE DESC
            OFFSET ' || v_offset || ' ROWS
            FETCH NEXT ' || p_page_size || ' ROWS ONLY';
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
        DBMS_OUTPUT.PUT_LINE(
            RPAD('№ ЗАКАЗА', 10) || ' | ' ||
            RPAD('ДАТА', 12) || ' | ' ||
            RPAD('ПОКУПАТЕЛЬ', 20) || ' | ' ||
            RPAD('СТАТУС', 15) || ' | ' ||
            RPAD('СУММА', 12) || ' | ' ||
            'ТОВАРЫ'
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
        
        CASE v_params_count
            WHEN 0 THEN
                OPEN v_cursor FOR v_sql;
            WHEN 1 THEN
                OPEN v_cursor FOR v_sql USING p_status;
            WHEN 2 THEN
                OPEN v_cursor FOR v_sql USING p_status, p_user_id;
            WHEN 3 THEN
                OPEN v_cursor FOR v_sql USING p_status, p_user_id, p_start_date;
            WHEN 4 THEN
                OPEN v_cursor FOR v_sql USING p_status, p_user_id, p_start_date, p_end_date;
        END CASE;
        
        LOOP
            FETCH v_cursor INTO 
                v_order_id, v_order_date, v_user_id_var, 
                v_first_name, v_last_name, v_status,
                v_total_amount, v_items_count;
            EXIT WHEN v_cursor%NOTFOUND;
            
            DBMS_OUTPUT.PUT_LINE(
                RPAD('# ' || v_order_id, 10) || ' | ' ||
                RPAD(format_date(v_order_date), 12) || ' | ' ||
                RPAD(
                    CASE 
                        WHEN v_first_name IS NOT NULL AND v_last_name IS NOT NULL THEN
                            mask_sensitive_data(v_first_name, 'NAME') || ' ' || 
                            mask_sensitive_data(v_last_name, 'NAME')
                        ELSE
                            'Пользователь #' || v_user_id_var
                    END, 20) || ' | ' ||
                RPAD(v_status, 15) || ' | ' ||
                RPAD(TO_CHAR(v_total_amount, '999,990.00'), 12) || ' | ' ||
                v_items_count || ' шт.'
            );
        END LOOP;
        
        CLOSE v_cursor;
        
        DBMS_OUTPUT.PUT_LINE(RPAD('═', 80, '═'));
        
    EXCEPTION
        WHEN OTHERS THEN
            IF v_cursor%ISOPEN THEN
                CLOSE v_cursor;
            END IF;
            DBMS_OUTPUT.PUT_LINE('Ошибка при поиске заказов: ' || SQLERRM);
    END;
    
    PROCEDURE get_order_statistics(
        p_start_date IN DATE DEFAULT TRUNC(SYSDATE) - 30,
        p_end_date IN DATE DEFAULT TRUNC(SYSDATE)
    ) IS
        v_total_orders NUMBER := 0;
        v_total_amount NUMBER := 0;
        v_avg_order_amount NUMBER := 0;
        v_max_order_amount NUMBER := 0;
        v_daily_avg_orders NUMBER := 0;
        v_days_count NUMBER;
    BEGIN
        AUTOPARTS_UTIL.CHECK_ACCESS('MANAGER');
        
        -- Подсчитываем количество дней в периоде
        v_days_count := p_end_date - p_start_date + 1;
        
        -- Получаем статистику
        BEGIN
            SELECT 
                COUNT(*) as TOTAL_ORDERS,
                SUM(TOTAL_AMOUNT) as TOTAL_AMOUNT,
                AVG(TOTAL_AMOUNT) as AVG_ORDER_AMOUNT,
                MAX(TOTAL_AMOUNT) as MAX_ORDER_AMOUNT
            INTO 
                v_total_orders,
                v_total_amount,
                v_avg_order_amount,
                v_max_order_amount
            FROM ORDERS
            WHERE TRUNC(ORDER_DATE) BETWEEN TRUNC(p_start_date) AND TRUNC(p_end_date);
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_total_orders := 0;
                v_total_amount := 0;
                v_avg_order_amount := 0;
                v_max_order_amount := 0;
        END;
        
        -- Вычисляем среднее количество заказов в день
        IF v_days_count > 0 THEN
            v_daily_avg_orders := ROUND(v_total_orders / v_days_count, 2);
        END IF;
        
        -- Выводим статистику
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('                   СТАТИСТИКА ЗАКАЗОВ');
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════');
        DBMS_OUTPUT.PUT_LINE('ПЕРИОД: ' || format_date(p_start_date) || ' - ' || format_date(p_end_date));
        DBMS_OUTPUT.PUT_LINE('Всего дней: ' || v_days_count);
        DBMS_OUTPUT.PUT_LINE('══════════════════════════════════════════════════════════' || CHR(10));
        
        DBMS_OUTPUT.PUT_LINE('  ОБЩАЯ СТАТИСТИКА:');
        DBMS_OUTPUT.PUT_LINE('  Всего заказов: ' || NVL(v_total_orders, 0));
        DBMS_OUTPUT.PUT_LINE('  Общая сумма: ' || TO_CHAR(NVL(v_total_amount, 0), '999,999,990.00') || ' руб.');
        DBMS_OUTPUT.PUT_LINE('  Средняя сумма заказа: ' || TO_CHAR(NVL(v_avg_order_amount, 0), '999,990.00') || ' руб.');
        DBMS_OUTPUT.PUT_LINE('  Максимальная сумма заказа: ' || TO_CHAR(NVL(v_max_order_amount, 0), '999,990.00') || ' руб.');
        DBMS_OUTPUT.PUT_LINE('  Среднее количество заказов в день: ' || v_daily_avg_orders);
        
        -- Статистика по статусам
        DBMS_OUTPUT.PUT_LINE(CHR(10) || ' СТАТИСТИКА ПО СТАТУСАМ:');
        FOR stat_rec IN (
            SELECT 
                STATUS,
                COUNT(*) as ORDER_COUNT,
                SUM(TOTAL_AMOUNT) as ORDER_AMOUNT
            FROM ORDERS
            WHERE TRUNC(ORDER_DATE) BETWEEN TRUNC(p_start_date) AND TRUNC(p_end_date)
            GROUP BY STATUS
            ORDER BY COUNT(*) DESC
        ) LOOP
            DECLARE
                v_percentage NUMBER;
            BEGIN
                v_percentage := ROUND(stat_rec.ORDER_COUNT * 100.0 / NULLIF(v_total_orders, 0), 2);
                DBMS_OUTPUT.PUT_LINE('  ' || stat_rec.STATUS || ': ' || stat_rec.ORDER_COUNT || 
                    ' заказов (' || v_percentage || '%), ' || 
                    TO_CHAR(NVL(stat_rec.ORDER_AMOUNT, 0), '999,990.00') || ' руб.');
            END;
        END LOOP;
        
        -- Статистика по дням недели
        DBMS_OUTPUT.PUT_LINE(CHR(10) || ' СТАТИСТИКА ПО ДНЯМ НЕДЕЛИ:');
        FOR day_stat IN (
            SELECT 
                TO_CHAR(ORDER_DATE, 'DAY', 'NLS_DATE_LANGUAGE=RUSSIAN') as DAY_NAME,
                COUNT(*) as ORDER_COUNT,
                SUM(TOTAL_AMOUNT) as TOTAL_AMOUNT
            FROM ORDERS
            WHERE TRUNC(ORDER_DATE) BETWEEN TRUNC(p_start_date) AND TRUNC(p_end_date)
            GROUP BY TO_CHAR(ORDER_DATE, 'DAY', 'NLS_DATE_LANGUAGE=RUSSIAN')
            ORDER BY ORDER_COUNT DESC
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || TRIM(day_stat.DAY_NAME) || ': ' || 
                day_stat.ORDER_COUNT || ' заказов, ' || 
                TO_CHAR(NVL(day_stat.TOTAL_AMOUNT, 0), '999,990.00') || ' руб.');
        END LOOP;
        
        -- Топ 10 пользователей по сумме заказов
        DBMS_OUTPUT.PUT_LINE(CHR(10) || ' ТОП-10 ПОКУПАТЕЛЕЙ:');
        FOR top_user_rec IN (
            SELECT 
                u.USER_ID,
                u.FIRST_NAME,
                u.LAST_NAME,
                COUNT(o.ORDER_ID) as ORDER_COUNT,
                SUM(o.TOTAL_AMOUNT) as TOTAL_SPENT
            FROM ORDERS o
            JOIN USERS u ON o.USER_ID = u.USER_ID
            WHERE TRUNC(o.ORDER_DATE) BETWEEN TRUNC(p_start_date) AND TRUNC(p_end_date)
            GROUP BY u.USER_ID, u.FIRST_NAME, u.LAST_NAME
            ORDER BY TOTAL_SPENT DESC
            FETCH FIRST 10 ROWS ONLY
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || 
                mask_sensitive_data(top_user_rec.FIRST_NAME, 'NAME') || ' ' || 
                mask_sensitive_data(top_user_rec.LAST_NAME, 'NAME') || 
                ' (ID: ' || top_user_rec.USER_ID || '): ' || 
                top_user_rec.ORDER_COUNT || ' заказов, ' || 
                TO_CHAR(top_user_rec.TOTAL_SPENT, '999,990.00') || ' руб.');
        END LOOP;
        
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Ошибка при получении статистики: ' || SQLERRM);
    END;

END AUTOPARTS_API_MANAGER;
/