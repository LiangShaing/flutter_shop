BEGIN;

INSERT INTO auth.users (id) VALUES ('11111111-1111-4111-8111-111111111111');
INSERT INTO public.merchant_users (user_id) VALUES ('11111111-1111-4111-8111-111111111111');
INSERT INTO public.menu_items (id, legacy_id, sid, item_type, menu_row, name, display_name, price, is_available)
VALUES ('22222222-2222-4222-8222-222222222222', 'legacy-1', 43, 'mainProduct', '2', '米粉', '湯', 50, true);

DO $$
DECLARE
  v_payload jsonb := jsonb_build_object(
    'order', jsonb_build_object(
      'id', '33333333-3333-4333-8333-333333333333', 'order_date', '2026-11-12T16:00:00Z',
      'business_date', '2026-11-13', 'takeout', 0, 'uber', 1, 'sauerkraut', 0, 'ginger', 1,
      'chili', 1, 'chili_level', 2, 'get_pay', 100, 'total_price', 100, 'mark', '測試'
    ),
    'items', jsonb_build_array(jsonb_build_object(
      'id', '44444444-4444-4444-8444-444444444444', 'order_id', '33333333-3333-4333-8333-333333333333',
      'menu_item_id', '55555555-5555-4555-8555-555555555555', 'menu_legacy_id', 'legacy-1',
      'sid', 43, 'item_type', 'mainProduct', 'name', '米粉', 'show_name', '湯', 'price', 50, 'quantity', 2
    ))
  );
  v_result jsonb;
  v_second jsonb;
  v_bad jsonb;
  v_duplicate_item jsonb;
BEGIN
  IF has_function_privilege('anon', 'public.submit_merchant_order(uuid,jsonb)', 'EXECUTE') OR
     NOT has_function_privilege('authenticated', 'public.submit_merchant_order(uuid,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Unexpected function permissions';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  BEGIN
    PERFORM public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', v_payload);
    RAISE EXCEPTION 'Anonymous submission unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-4000-8000-000000000000', true);
  BEGIN
    PERFORM public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', v_payload);
    RAISE EXCEPTION 'Non-merchant submission unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  PERFORM set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
  v_result := public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', v_payload);
  IF (v_result ->> 'serial')::integer <> 10 OR v_result ->> 'business_date' <> '2026-11-13' THEN
    RAISE EXCEPTION 'Unexpected first serial: %', v_result;
  END IF;
  IF public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', v_payload) IS DISTINCT FROM v_result THEN
    RAISE EXCEPTION 'Repeated operation returned a different result';
  END IF;
  UPDATE public.orders SET serial = 13 WHERE id = '33333333-3333-4333-8333-333333333333';
  BEGIN
    PERFORM public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', v_payload);
    RAISE EXCEPTION 'Altered official serial unexpectedly accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'SERVER_ORDER_CHANGED' THEN RAISE; END IF;
  END;
  UPDATE public.orders SET serial = 10 WHERE id = '33333333-3333-4333-8333-333333333333';
  UPDATE public.merchant_users SET is_active = false WHERE user_id = '11111111-1111-4111-8111-111111111111';
  BEGIN
    PERFORM public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', v_payload);
    RAISE EXCEPTION 'Inactive merchant unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  UPDATE public.merchant_users SET is_active = true WHERE user_id = '11111111-1111-4111-8111-111111111111';
  IF NOT EXISTS (
    SELECT 1 FROM public.orders WHERE id = '33333333-3333-4333-8333-333333333333'
      AND serial = 10 AND chili_level = 2 AND chili AND uber AND NOT takeout
  ) OR NOT EXISTS (
    SELECT 1 FROM public.order_items WHERE order_id = '33333333-3333-4333-8333-333333333333'
      AND menu_item_id = '22222222-2222-4222-8222-222222222222' AND unit_price = 50 AND quantity = 2
  ) THEN
    RAISE EXCEPTION 'Order or item snapshot is incorrect';
  END IF;
  BEGIN
    INSERT INTO public.orders (id, takeout, serial, total_price, get_pay, order_date)
    VALUES ('abababab-abab-4aba-8aba-abababababab', false, 10, 1, 0, '2026-11-12T16:30:00Z');
    RAISE EXCEPTION 'Duplicate same-day serial unexpectedly succeeded';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
  BEGIN
    PERFORM public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', jsonb_set(v_payload, '{order,mark}', '"changed"'));
    RAISE EXCEPTION 'Changed retry unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'IDEMPOTENCY_CONFLICT' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM public.submit_merchant_order('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', v_payload);
    RAISE EXCEPTION 'Duplicate order unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'ORDER_ID_CONFLICT' THEN RAISE; END IF;
  END;

  v_second := jsonb_set(v_payload, '{order,id}', '"66666666-6666-4666-8666-666666666666"');
  v_second := jsonb_set(v_second, '{items,0,id}', '"77777777-7777-4777-8777-777777777777"');
  v_second := jsonb_set(v_second, '{items,0,order_id}', '"66666666-6666-4666-8666-666666666666"');
  UPDATE public.menu_items SET price = 60 WHERE legacy_id = 'legacy-1';
  BEGIN
    PERFORM public.submit_merchant_order('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', v_second);
    RAISE EXCEPTION 'Changed menu unexpectedly accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'MENU_CONFLICT' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM public.orders WHERE id = '66666666-6666-4666-8666-666666666666') THEN
    RAISE EXCEPTION 'Conflict left a partial order';
  END IF;
  UPDATE public.menu_items SET price = 50 WHERE legacy_id = 'legacy-1';
  v_result := public.submit_merchant_order('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', v_second);
  IF (v_result ->> 'serial')::integer <> 11 THEN
    RAISE EXCEPTION 'Conflict consumed a number: %', v_result;
  END IF;

  v_second := jsonb_set(v_second, '{order,id}', '"88888888-8888-4888-8888-888888888888"');
  v_second := jsonb_set(v_second, '{items,0,id}', '"99999999-9999-4999-8999-999999999999"');
  v_second := jsonb_set(v_second, '{items,0,order_id}', '"88888888-8888-4888-8888-888888888888"');
  v_second := jsonb_set(v_second, '{order,order_date}', '"2026-11-13T16:00:00Z"');
  v_second := jsonb_set(v_second, '{order,business_date}', '"2026-11-14"');
  v_result := public.submit_merchant_order('cccccccc-cccc-4ccc-8ccc-cccccccccccc', v_second);
  IF (v_result ->> 'serial')::integer <> 10 OR v_result ->> 'business_date' <> '2026-11-14' THEN
    RAISE EXCEPTION 'Taipei business day did not reset: %', v_result;
  END IF;

  INSERT INTO public.orders (id, takeout, serial, total_price, get_pay, order_date)
  VALUES ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', false, 20, 1, 0, '2026-11-14T16:00:00Z');
  v_second := jsonb_set(v_second, '{order,id}', '"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"');
  v_second := jsonb_set(v_second, '{items,0,id}', '"ffffffff-ffff-4fff-8fff-ffffffffffff"');
  v_second := jsonb_set(v_second, '{items,0,order_id}', '"eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"');
  v_second := jsonb_set(v_second, '{order,order_date}', '"2026-11-14T16:00:00Z"');
  v_second := jsonb_set(v_second, '{order,business_date}', '"2026-11-15"');
  v_result := public.submit_merchant_order('dddddddd-0000-4000-8000-000000000000', v_second);
  IF (v_result ->> 'serial')::integer <> 21 THEN
    RAISE EXCEPTION 'Existing orders were not considered: %', v_result;
  END IF;

  BEGIN
    PERFORM public.submit_merchant_order('eeeeeeee-0000-4000-8000-000000000000', jsonb_set(v_second, '{order,id}', '"abcdabcd-abcd-4abc-8abc-abcdabcdabcd"'));
    RAISE EXCEPTION 'Mismatched item order ID unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'INVALID_ORDER_ITEM' THEN RAISE; END IF;
  END;

  v_second := jsonb_set(v_second, '{order,id}', '"abcdabcd-abcd-4abc-8abc-abcdabcdabcd"');
  v_second := jsonb_set(v_second, '{items,0,id}', '"12345678-1234-4234-8234-123456789012"');
  v_second := jsonb_set(v_second, '{items,0,order_id}', '"abcdabcd-abcd-4abc-8abc-abcdabcdabcd"');
  v_second := jsonb_set(v_second, '{items,0,quantity}', '3000000000');
  v_second := jsonb_set(v_second, '{order,total_price}', '150000000000');
  v_second := jsonb_set(v_second, '{order,get_pay}', '5000000000');
  v_result := public.submit_merchant_order('eeeeeeee-0000-4000-8000-000000000000', v_second);
  IF (v_result ->> 'serial')::integer <> 22 OR NOT EXISTS (
    SELECT 1 FROM public.orders WHERE id = 'abcdabcd-abcd-4abc-8abc-abcdabcdabcd'
      AND total_price = 150000000000 AND get_pay = 5000000000
  ) OR NOT EXISTS (
    SELECT 1 FROM public.order_items WHERE id = '12345678-1234-4234-8234-123456789012'
      AND quantity = 3000000000
  ) THEN
    RAISE EXCEPTION '64-bit values were not preserved';
  END IF;

  v_bad := jsonb_set(v_second, '{order,id}', '"12121212-1212-4212-8212-121212121212"');
  v_bad := jsonb_set(v_bad, '{items,0,id}', '"34343434-3434-4343-8343-343434343434"');
  v_bad := jsonb_set(v_bad, '{items,0,order_id}', '"12121212-1212-4212-8212-121212121212"');
  v_duplicate_item := v_bad -> 'items' -> 0;
  v_bad := jsonb_set(v_bad, '{items}', jsonb_build_array(v_duplicate_item, v_duplicate_item));
  v_bad := jsonb_set(v_bad, '{order,total_price}', '300000000000');
  BEGIN
    PERFORM public.submit_merchant_order('ffffffff-0000-4000-8000-000000000000', v_bad);
    RAISE EXCEPTION 'Duplicate detail unexpectedly succeeded';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.orders WHERE id = '12121212-1212-4212-8212-121212121212') OR
     EXISTS (SELECT 1 FROM public.order_items WHERE id = '34343434-3434-4343-8343-343434343434') OR
     (SELECT last_serial FROM public.order_daily_counters WHERE business_date = '2026-11-15') <> 22 THEN
    RAISE EXCEPTION 'Failed detail insertion left partial data or consumed a serial';
  END IF;
  v_bad := jsonb_set(v_bad, '{items}', jsonb_build_array(v_duplicate_item));
  v_bad := jsonb_set(v_bad, '{order,total_price}', '150000000000');
  v_result := public.submit_merchant_order('ffffffff-0000-4000-8000-000000000000', v_bad);
  IF (v_result ->> 'serial')::integer <> 23 THEN
    RAISE EXCEPTION 'Failed detail insertion consumed a serial: %', v_result;
  END IF;
  PERFORM set_config('test.merchant_payload', v_payload::text, true);
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
DO $$
DECLARE
  v_result jsonb;
BEGIN
  IF has_table_privilege(current_user, 'public.order_daily_counters', 'SELECT') OR
     has_table_privilege(current_user, 'public.order_write_operations', 'SELECT') THEN
    RAISE EXCEPTION 'Internal tables are accessible to authenticated clients';
  END IF;
  BEGIN
    PERFORM public.submit_merchant_order(NULL, '{}'::jsonb);
    RAISE EXCEPTION 'Invalid submission unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'INVALID_ORDER' THEN RAISE; END IF;
  END;
  v_result := public.submit_merchant_order(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    current_setting('test.merchant_payload')::jsonb
  );
  IF (v_result ->> 'serial')::integer <> 10 THEN
    RAISE EXCEPTION 'Authenticated retry did not return the original serial';
  END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM public.submit_merchant_order('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '{}'::jsonb);
    RAISE EXCEPTION 'Anonymous role unexpectedly invoked the RPC';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END;
$$;
RESET ROLE;

ROLLBACK;