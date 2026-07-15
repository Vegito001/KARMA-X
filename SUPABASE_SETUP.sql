-- KarmaX Avatar System Supabase Setup

-- Table: avatars
-- Static table containing all available avatar archetypes
CREATE TABLE IF NOT EXISTS avatars (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  archetype TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  default_stat TEXT NOT NULL,
  color_hex TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Table: user_avatar_progress
-- Dynamic table tracking each user's avatar selection and progress
CREATE TABLE IF NOT EXISTS user_avatar_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  selected_avatar_id UUID NOT NULL REFERENCES avatars(id),
  current_level INTEGER NOT NULL DEFAULT 1,
  dominant_stat TEXT NOT NULL DEFAULT 'health',
  equipped_badges TEXT[] DEFAULT ARRAY[]::TEXT[],
  last_updated TIMESTAMP NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_user FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);

-- Seed avatar data
INSERT INTO avatars (name, archetype, description, default_stat, color_hex) VALUES
  ('Noble Knight', 'knight', 'A steadfast warrior, strong in discipline and honor.', 'discipline', '#FFD54F'),
  ('Mystic Sage', 'sage', 'A seeker of knowledge, mastering the arcane arts.', 'knowledge', '#5B7FFF'),
  ('Swift Rogue', 'rogue', 'Quick and cunning, balanced in all aspects.', 'social', '#4ECDC4'),
  ('Steadfast Guardian', 'guardian', 'Protector of wellness, radiating vitality.', 'health', '#FF6B4A'),
  ('Arcane Mage', 'mage', 'Master of mystical forces and transformation.', 'knowledge', '#9D5FFF'),
  ('Natural Druid', 'druid', 'Harmonious with nature, balanced and resilient.', 'health', '#52C977')
ON CONFLICT (archetype) DO NOTHING;

-- Create indexes
CREATE INDEX idx_user_avatar_progress_user_id ON user_avatar_progress(user_id);
CREATE INDEX idx_user_avatar_progress_selected_avatar_id ON user_avatar_progress(selected_avatar_id);
CREATE INDEX idx_avatars_archetype ON avatars(archetype);

-- Enable RLS for security
ALTER TABLE avatars ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_avatar_progress ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Avatars: readable by all authenticated users
CREATE POLICY "avatars_readable_by_authenticated" ON avatars
  FOR SELECT
  TO authenticated
  USING (TRUE);

-- user_avatar_progress: users can only see/edit their own
CREATE POLICY "user_avatar_progress_readable_by_owner" ON user_avatar_progress
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "user_avatar_progress_writable_by_owner" ON user_avatar_progress
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_avatar_progress_insertable_by_authenticated" ON user_avatar_progress
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Cleanup old records (optional)
-- ALTER TABLE user_avatar_progress
-- ADD CONSTRAINT one_avatar_per_user UNIQUE (user_id);
