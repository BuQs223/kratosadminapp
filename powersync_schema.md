bucket_definitions:
  # Member app buckets
  user_profile:
    parameters: |
      SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM profiles WHERE id = bucket.user_id
  user_memberships:
    parameters: |
      SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM memberships WHERE user_id = bucket.user_id
  user_family_memberships:
    parameters: |
      SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM family_memberships WHERE user_id = bucket.user_id
  user_family_linked_memberships:
    parameters: |
      SELECT membership_id
      FROM family_memberships
      WHERE user_id = request.user_id()
    data:
      - SELECT * FROM memberships WHERE id = bucket.membership_id
  user_check_ins:
    parameters: |
      SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM check_ins WHERE user_id = bucket.user_id
  # Public buckets
  gyms:
    data:
      - SELECT * FROM gyms
  membership_plans:
    data:
      - SELECT * FROM membership_plans WHERE is_active = true
  membership_plan_access:
    data:
      - |
        SELECT plan_id || '_' || gym_id AS id, plan_id, gym_id
        FROM membership_plan_access
  # Admin app buckets
  admin_core_data:
    parameters: |
      SELECT 'admin' AS access_group
      FROM profiles
      WHERE id = request.user_id() AND is_admin = true
    data:
      - SELECT * FROM profiles WHERE bucket.access_group = 'admin'
      - SELECT * FROM memberships WHERE bucket.access_group = 'admin'
      - SELECT * FROM family_memberships WHERE bucket.access_group = 'admin'
      - SELECT * FROM membership_events WHERE bucket.access_group = 'admin'
      - SELECT * FROM gyms WHERE bucket.access_group = 'admin'
      - SELECT * FROM membership_plans WHERE bucket.access_group = 'admin'
      - |
        SELECT plan_id || '_' || gym_id AS id, plan_id, gym_id
        FROM membership_plan_access
        WHERE bucket.access_group = 'admin'
      - SELECT * FROM employees WHERE bucket.access_group = 'admin'
      - SELECT * FROM revenue_ledger WHERE bucket.access_group = 'admin'
      - SELECT * FROM admin_analytics_summary WHERE bucket.access_group = 'admin'
  admin_check_ins:
    parameters: |
      SELECT 'admin' AS access_group
      FROM profiles
      WHERE id = request.user_id() AND is_admin = true
    data:
      - SELECT * FROM check_ins WHERE bucket.access_group = 'admin'
  # Employee app buckets
  employee_gym_products:
    parameters: |
      SELECT gym_id
      FROM employees
      WHERE user_id = request.user_id() AND is_active = true
    data:
      - |
        SELECT *
        FROM products
        WHERE gym_id = bucket.gym_id
      - |
        SELECT *
        FROM product_sales
        WHERE gym_id = bucket.gym_id
      - |
        SELECT *
        FROM product_sale_items
        WHERE gym_id = bucket.gym_id
      - |
        SELECT *
        FROM product_stock_movements
        WHERE gym_id = bucket.gym_id
  employee_shared_data:
    parameters: |
      SELECT 'all_staff' AS access_group
      FROM employees
      WHERE user_id = request.user_id() AND is_active = true
    data:
      - |
        SELECT *
        FROM memberships
        WHERE bucket.access_group = 'all_staff'
          AND is_active = true
          AND canceled_at IS NULL
      - |
        SELECT id, full_name, phone, email, created_at
        FROM profiles
        WHERE bucket.access_group = 'all_staff'
      - |
        SELECT id, user_id, public_key_pem, key_version, algorithm, created_at, updated_at
        FROM user_public_keys
        WHERE bucket.access_group = 'all_staff'
          AND revoked_at IS NULL
      - SELECT * FROM family_memberships WHERE bucket.access_group = 'all_staff'
      - SELECT * FROM membership_events WHERE bucket.access_group = 'all_staff'
      - |
        SELECT *
        FROM membership_upgrade_rules
        WHERE bucket.access_group = 'all_staff'
          AND is_active = true
      - SELECT * FROM membership_upgrades WHERE bucket.access_group = 'all_staff'
      - SELECT * FROM employees WHERE bucket.access_group = 'all_staff'
      - SELECT * FROM revenue_ledger WHERE bucket.access_group = 'all_staff'
      - SELECT * FROM check_ins WHERE bucket.access_group = 'all_staff'
  employee_self:
    parameters: |
      SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM employees WHERE user_id = bucket.user_id AND is_active = true
