ALTER TABLE public.orders
  ALTER COLUMN total_price TYPE bigint,
  ALTER COLUMN get_pay TYPE bigint,
  ADD COLUMN business_date date GENERATED ALWAYS AS ((order_date AT TIME ZONE 'Asia/Taipei')::date) STORED,
  ADD COLUMN chili_level integer CHECK (chili_level BETWEEN 0 AND 3),
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.order_items
  ALTER COLUMN quantity TYPE bigint,
  ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX orders_business_date_serial_unique
  ON public.orders(business_date, serial);

CREATE TABLE public.order_daily_counters (
  business_date date PRIMARY KEY,
  last_serial integer NOT NULL CHECK (last_serial >= 10)
);

CREATE TABLE public.order_write_operations (
  operation_id uuid PRIMARY KEY,
  order_id uuid NOT NULL UNIQUE REFERENCES public.orders(id),
  merchant_user_id uuid NOT NULL REFERENCES auth.users(id),
  request_payload jsonb NOT NULL,
  business_date date NOT NULL,
  serial integer NOT NULL CHECK (serial >= 10),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.order_daily_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_write_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.order_daily_counters, public.order_write_operations FROM PUBLIC, anon, authenticated;

CREATE FUNCTION public.submit_merchant_order(p_operation_id uuid, p_payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_order jsonb;
  v_items jsonb;
  v_item jsonb;
  v_order_id uuid;
  v_existing public.order_write_operations%ROWTYPE;
  v_menu public.menu_items%ROWTYPE;
  v_category_active boolean;
  v_order_date timestamptz;
  v_business_date date;
  v_serial integer;
  v_spice integer;
  v_received bigint;
  v_quantity bigint;
  v_total numeric := 0;
  v_takeout boolean;
  v_uber boolean;
BEGIN
  PERFORM 1 FROM public.merchant_users WHERE user_id = v_user_id AND is_active FOR SHARE;
  IF v_user_id IS NULL OR NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'MERCHANT_AUTH_REQUIRED';
  END IF;
  IF p_operation_id IS NULL OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER';
  END IF;
  v_order := p_payload -> 'order';
  v_items := p_payload -> 'items';
  IF jsonb_typeof(v_order) IS DISTINCT FROM 'object' OR jsonb_typeof(v_items) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER';
  END IF;
  IF jsonb_array_length(v_items) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER';
  END IF;
  v_order_id := (v_order ->> 'id')::uuid;
  IF v_order_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('operation:' || p_operation_id::text, 0));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('order:' || v_order_id::text, 0));
  SELECT * INTO v_existing FROM public.order_write_operations WHERE operation_id = p_operation_id;
  IF FOUND THEN
    IF v_existing.order_id IS DISTINCT FROM v_order_id OR v_existing.request_payload IS DISTINCT FROM p_payload THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'IDEMPOTENCY_CONFLICT';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.orders
      WHERE id = v_order_id AND serial = v_existing.serial AND business_date = v_existing.business_date
    ) THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'SERVER_ORDER_CHANGED';
    END IF;
    RETURN jsonb_build_object('operation_id', p_operation_id, 'order_id', v_order_id,
      'serial', v_existing.serial, 'business_date', v_existing.business_date);
  END IF;
  IF EXISTS (SELECT 1 FROM public.orders WHERE id = v_order_id) THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'ORDER_ID_CONFLICT';
  END IF;

  IF COALESCE(v_order ->> 'order_date', '') !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER_DATE';
  END IF;
  v_order_date := (v_order ->> 'order_date')::timestamptz;
  v_business_date := (v_order_date AT TIME ZONE 'Asia/Taipei')::date;
  IF v_order ->> 'business_date' IS DISTINCT FROM v_business_date::text THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'BUSINESS_DATE_MISMATCH';
  END IF;
  IF COALESCE(v_order ->> 'takeout', '') NOT IN ('0', '1') OR
     COALESCE(v_order ->> 'uber', '') NOT IN ('0', '1') OR
     COALESCE(v_order ->> 'sauerkraut', '') NOT IN ('0', '1') OR
     COALESCE(v_order ->> 'ginger', '') NOT IN ('0', '1') OR
     COALESCE(v_order ->> 'chili', '') NOT IN ('0', '1') THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER_OPTIONS';
  END IF;
  v_takeout := v_order ->> 'takeout' = '1';
  v_uber := v_order ->> 'uber' = '1';
  v_spice := (v_order ->> 'chili_level')::integer;
  v_received := (v_order ->> 'get_pay')::bigint;
  IF (v_takeout AND v_uber) OR v_spice IS NULL OR v_spice NOT BETWEEN 0 AND 3 OR
     (v_order ->> 'chili' = '1') IS DISTINCT FROM (v_spice > 0) OR
     v_received IS NULL OR v_received < 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER_OPTIONS';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    IF jsonb_typeof(v_item) IS DISTINCT FROM 'object' OR
       v_item ->> 'id' IS NULL OR v_item ->> 'order_id' IS DISTINCT FROM v_order_id::text OR
       (v_item ->> 'menu_legacy_id' IS NULL AND v_item ->> 'menu_item_id' IS NULL) THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER_ITEM';
    END IF;
    v_quantity := (v_item ->> 'quantity')::bigint;
    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER_ITEM';
    END IF;
    IF v_item ->> 'menu_legacy_id' IS NOT NULL THEN
      SELECT * INTO v_menu FROM public.menu_items WHERE legacy_id = v_item ->> 'menu_legacy_id' FOR SHARE;
    ELSE
      SELECT * INTO v_menu FROM public.menu_items WHERE id = (v_item ->> 'menu_item_id')::uuid FOR SHARE;
    END IF;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'MENU_CONFLICT';
    END IF;
    IF v_menu.category_id IS NOT NULL THEN
      SELECT is_active INTO v_category_active FROM public.categories WHERE id = v_menu.category_id FOR SHARE;
      IF NOT FOUND OR NOT v_category_active THEN
        RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'MENU_CONFLICT';
      END IF;
    END IF;
    IF NOT v_menu.is_available OR v_menu.sid IS DISTINCT FROM (v_item ->> 'sid')::integer OR
       v_menu.item_type IS DISTINCT FROM v_item ->> 'item_type' OR
       v_menu.name IS DISTINCT FROM v_item ->> 'name' OR
       v_menu.display_name IS DISTINCT FROM v_item ->> 'show_name' OR
       v_menu.price IS DISTINCT FROM (v_item ->> 'price')::integer THEN
      RAISE EXCEPTION USING ERRCODE = 'P0001', MESSAGE = 'MENU_CONFLICT';
    END IF;
    v_total := v_total + v_menu.price::numeric * v_quantity;
  END LOOP;
  IF v_total <= 0 OR v_total > 9223372036854775807 OR v_total IS DISTINCT FROM (v_order ->> 'total_price')::numeric THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_ORDER_TOTAL';
  END IF;

  INSERT INTO public.order_daily_counters AS counter (business_date, last_serial)
  VALUES (
    v_business_date,
    GREATEST(COALESCE((SELECT MAX(serial) FROM public.orders WHERE business_date = v_business_date), 9), 9) + 1
  )
  ON CONFLICT (business_date) DO UPDATE
    SET last_serial = GREATEST(counter.last_serial, COALESCE((SELECT MAX(serial) FROM public.orders WHERE business_date = v_business_date), 9)) + 1
  RETURNING last_serial INTO v_serial;

  INSERT INTO public.orders (
    id, order_source, status, takeout, serial, total_price, get_pay, sauerkraut, ginger,
    chili, chili_level, order_date, uber, mark, created_at
  ) VALUES (
    v_order_id, CASE WHEN v_uber THEN 'UBER' ELSE 'POS_APP' END, 'PENDING', v_takeout,
    v_serial, v_total::bigint, v_received, v_order ->> 'sauerkraut' = '1',
    v_order ->> 'ginger' = '1', v_spice > 0, v_spice, v_order_date, v_uber,
    v_order ->> 'mark', v_order_date
  );
  FOR v_item IN SELECT value FROM jsonb_array_elements(v_items) LOOP
    SELECT id INTO v_menu.id FROM public.menu_items
    WHERE (v_item ->> 'menu_legacy_id' IS NOT NULL AND legacy_id = v_item ->> 'menu_legacy_id')
       OR (v_item ->> 'menu_legacy_id' IS NULL AND id = (v_item ->> 'menu_item_id')::uuid);
    INSERT INTO public.order_items (id, order_id, menu_item_id, sid, item_type, item_name, display_name, quantity, unit_price)
    VALUES (
      (v_item ->> 'id')::uuid, v_order_id, v_menu.id, (v_item ->> 'sid')::integer,
      v_item ->> 'item_type', v_item ->> 'name', v_item ->> 'show_name',
      (v_item ->> 'quantity')::bigint, (v_item ->> 'price')::integer
    );
  END LOOP;
  INSERT INTO public.order_write_operations (operation_id, order_id, merchant_user_id, request_payload, business_date, serial)
  VALUES (p_operation_id, v_order_id, v_user_id, p_payload, v_business_date, v_serial);
  RETURN jsonb_build_object('operation_id', p_operation_id, 'order_id', v_order_id, 'serial', v_serial, 'business_date', v_business_date);
END;
$$;

REVOKE ALL ON FUNCTION public.submit_merchant_order(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_merchant_order(uuid, jsonb) TO authenticated;