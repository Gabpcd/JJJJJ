-- 1. Update code prefix from SD- to JO-
CREATE OR REPLACE FUNCTION fn_generer_code_parrainage()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_code TEXT;
BEGIN
    v_code := 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    WHILE EXISTS (SELECT 1 FROM soignants WHERE code_parrainage = v_code) LOOP
        v_code := 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6));
    END LOOP;
    RETURN v_code;
END;
$$;

-- 2. Auto-generate on insert trigger
CREATE OR REPLACE FUNCTION fn_auto_code_parrainage()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.code_parrainage IS NULL OR NEW.code_parrainage = '' THEN
        NEW.code_parrainage := fn_generer_code_parrainage();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_code_parrainage ON soignants;
CREATE TRIGGER trg_auto_code_parrainage
    BEFORE INSERT ON soignants
    FOR EACH ROW
    EXECUTE FUNCTION fn_auto_code_parrainage();

-- 3. Generate for existing soignants
UPDATE soignants
SET code_parrainage = 'JO-' || UPPER(SUBSTRING(encode(gen_random_bytes(4), 'hex') FROM 1 FOR 6))
WHERE code_parrainage IS NULL OR code_parrainage = '' OR code_parrainage LIKE 'SD-%';

-- 4. Unique constraint on paiements_mission.mission_id
ALTER TABLE paiements_mission ADD CONSTRAINT IF NOT EXISTS uq_paiements_mission_mission_id UNIQUE (mission_id);
