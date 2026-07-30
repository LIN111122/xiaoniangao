-- ============================================================
-- 小年糕 · 家庭同步后端  Supabase 建表 SQL（含「防篡改」）
-- 用法：登录 supabase.com → 项目 → SQL Editor →
--       粘贴下面全部内容 → 点击 Run。
-- 建好后到 Settings → API 复制：
--   - Project URL        -> 填 App「Supabase 地址」
--   - anon public key    -> 填 App「Anon 公开密钥」
-- ============================================================
--
-- 【防篡改说明】
-- 仓库已设为公开，anon key 随之公开。为避免他人枚举房间码后篡改/删除你的数据：
--   1) 新增 wkey 列（隐藏的「写入密钥」），只有扫码/导入配置的人持有（写进 ?cfg= 里）。
--   2) 用 SECURITY DEFINER 函数 xng_verify_wkey 校验写入密钥，anon 无 wkey 列读权限也能量。
--   3) 收回 anon 的 DELETE 权限，并隐藏 wkey 列（不可 SELECT）。
-- 注意：宝宝真实数据仍由「同步密码」端到端加密，本加固只防“被改/被删”。
-- ============================================================

-- 1) 家庭状态表：每个「家庭房间码」对应一行
CREATE TABLE IF NOT EXISTS public.family_state (
  room       text PRIMARY KEY,
  rev        integer NOT NULL DEFAULT 1,
  data       jsonb   NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.family_state ADD COLUMN IF NOT EXISTS wkey text NOT NULL DEFAULT '';

-- 2) 防篡改校验函数（SECURITY DEFINER：以表所有者身份读 wkey，绕过列权限）
CREATE OR REPLACE FUNCTION public.xng_verify_wkey(p_room text, p_wkey text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v text;
BEGIN
  IF p_wkey IS NULL OR p_wkey = '' THEN RETURN false; END IF;
  SELECT wkey INTO v FROM public.family_state WHERE room = p_room;
  IF v IS NULL THEN RETURN false; END IF;
  IF v = p_wkey THEN RETURN true; END IF;
  IF v = '' THEN RETURN true; END IF;
  RETURN false;
END;
$$;
GRANT EXECUTE ON FUNCTION public.xng_verify_wkey(text, text) TO anon, authenticated;

-- 3) 重置并细化权限
REVOKE ALL ON public.family_state FROM anon, authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT (room, rev, data, updated_at) ON public.family_state TO anon, authenticated;
GRANT INSERT (room, rev, data, wkey)              ON public.family_state TO anon, authenticated;
GRANT UPDATE (rev, data, wkey)                   ON public.family_state TO anon, authenticated;

-- 4) 开启行级安全（RLS）
ALTER TABLE public.family_state ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_family_sync"            ON public.family_state;
DROP POLICY IF EXISTS "anon_family_sync_select"     ON public.family_state;
DROP POLICY IF EXISTS "anon_family_sync_insert"     ON public.family_state;
DROP POLICY IF EXISTS "anon_family_sync_update"     ON public.family_state;
CREATE POLICY "anon_family_sync_select"
  ON public.family_state FOR SELECT TO anon, authenticated USING ( true );
CREATE POLICY "anon_family_sync_insert"
  ON public.family_state FOR INSERT TO anon, authenticated WITH CHECK ( true );
CREATE POLICY "anon_family_sync_update"
  ON public.family_state FOR UPDATE TO anon, authenticated
  USING ( true )
  WITH CHECK ( public.xng_verify_wkey(room, wkey) );

-- 5) 加速按房间码查询
CREATE INDEX IF NOT EXISTS idx_family_state_room ON public.family_state (room);

-- 6) 刷新 PostgREST schema 缓存，让 REST 接口识别新增的 wkey 列
--    （否则 App 写入 wkey 时会报「找不到该列」的错误）
NOTIFY pgrst, 'reload schema';

SELECT room, rev, updated_at, 'schema reloaded' AS note FROM public.family_state LIMIT 1;
