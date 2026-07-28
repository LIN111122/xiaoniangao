-- ============================================================
-- 小年糕 · 家庭同步后端  Supabase 建表 SQL
-- 用法：登录 supabase.com → 新建项目 → SQL Editor →
--       粘贴下面全部内容 → 点击 Run。
-- 建好后到 Settings → API 复制：
--   - Project URL        -> 填 App「Supabase 地址」
--   - anon public key    -> 填 App「Anon 公开密钥」
-- ============================================================

-- 1) 家庭状态表：每个「家庭房间码」对应一行
CREATE TABLE IF NOT EXISTS public.family_state (
  room       text PRIMARY KEY,                       -- 家庭房间码（共享钥匙）
  rev        integer NOT NULL DEFAULT 1,            -- 版本号，用于乐观并发控制
  data       jsonb   NOT NULL,                      -- 全家合并后的全部数据
  updated_at timestamptz NOT NULL DEFAULT now()     -- 最后更新时间
);

-- 2) 显式授予底层表权限（关键！少了这步会报 42501 insufficient_privilege）
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.family_state TO anon, authenticated;

-- 3) 开启行级安全（RLS），所有访问都走策略
ALTER TABLE public.family_state ENABLE ROW LEVEL SECURITY;

-- 3) 匿名(anon)策略：房间码即共享密钥，知道房间码的人即可读写该房间
--    注意：anon key 是公开密钥，真正的隔离靠「房间码」不可猜测。
--    不要把房间码泄露给家人以外的人。
-- 4) 数据安全补充说明：若在 App「家庭同步」里设置了「同步密码」，数据在上传前会用
--    Web Crypto(AES-GCM) 在手机端加密，Supabase 只存密文；即使房间码泄露，没有密码
--    也读不到内容。不设密码则为明文存储（data 列直接是 JSON 对象）。两种模式共用同一张表。
DROP POLICY IF EXISTS "anon_family_sync" ON public.family_state;
CREATE POLICY "anon_family_sync"
  ON public.family_state
  FOR ALL
  TO anon, authenticated
  USING ( true )
  WITH CHECK ( true );

-- 4) 加速按房间码查询
CREATE INDEX IF NOT EXISTS idx_family_state_room ON public.family_state (room);

-- 验证：应能看到一张空表
SELECT * FROM public.family_state LIMIT 1;
