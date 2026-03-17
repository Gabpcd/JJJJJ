import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';

const SUPABASE_URL = 'https://flripxtsyegjshnhzjkz.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZscmlweHRzeWVnanNobmh6amt6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMyMTk2OTYsImV4cCI6MjA4ODc5NTY5Nn0.ywor0oGht7aYi8J1YwNRo_rfmJtQ6GBodmCp1kAB3UY';

export const publicSupabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
    storageKey: 'jolene-public-search',
  },
});
