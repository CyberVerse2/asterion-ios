import {
  boolean,
  doublePrecision,
  index,
  integer,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
} from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: text("id").primaryKey(),
  clerkUserId: text("clerk_user_id").notNull(),
  email: text("email"),
  username: text("username"),
  avatarUrl: text("avatar_url"),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("users_clerk_user_id_key").on(table.clerkUserId),
]);

export const readingProgress = pgTable("reading_progress", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  novelId: text("novel_id").notNull(),
  chapterId: text("chapter_id").notNull(),
  currentLine: integer("current_line").notNull().default(0),
  totalLines: integer("total_lines").notNull().default(0),
  percentage: doublePrecision("percentage").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("user_novel_progress_unique").on(table.userId, table.novelId),
  index("reading_progress_user_updated_idx").on(table.userId, table.updatedAt),
  index("reading_progress_user_novel_idx").on(table.userId, table.novelId),
]);

export const bookmarks = pgTable("bookmarks", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  novelId: text("novel_id").notNull(),
  chapterId: text("chapter_id").notNull(),
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("bookmark_user_chapter_unique").on(table.userId, table.chapterId),
  index("bookmark_user_novel_idx").on(table.userId, table.novelId),
  index("bookmark_user_created_idx").on(table.userId, table.createdAt),
]);

export const readingHistory = pgTable("reading_history", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  novelId: text("novel_id").notNull(),
  chapterId: text("chapter_id").notNull(),
  visitedAt: timestamp("visited_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  index("reading_history_user_visited_idx").on(table.userId, table.visitedAt),
  index("reading_history_user_novel_idx").on(table.userId, table.novelId),
]);

export const userPreferences = pgTable("user_preferences", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  readingGoal: integer("reading_goal").notNull().default(30),
  darkMode: boolean("dark_mode").notNull().default(true),
  notificationsOn: boolean("notifications_on").notNull().default(true),
  fontSizePref: text("font_size_pref").notNull().default("medium"),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("user_preferences_user_unique").on(table.userId),
]);

export const userLibraryNovels = pgTable("user_library_novels", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  novelId: text("novel_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("user_library_novel_unique").on(table.userId, table.novelId),
  index("user_library_user_created_idx").on(table.userId, table.createdAt),
]);

export const mediaBookmarks = pgTable("media_bookmarks", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  mediaType: text("media_type").notNull(),
  contentId: text("content_id").notNull(),
  title: text("title").notNull(),
  subtitle: text("subtitle"),
  imageUrl: text("image_url"),
  isSaved: boolean("is_saved").notNull().default(true),
  clientUpdatedAt: timestamp("client_updated_at", { withTimezone: true, mode: "date" }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("media_bookmark_user_content_unique").on(table.userId, table.mediaType, table.contentId),
  index("media_bookmark_user_updated_idx").on(table.userId, table.updatedAt),
]);

export const mediaPlaybackProgress = pgTable("media_playback_progress", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  mediaType: text("media_type").notNull(),
  contentId: text("content_id").notNull(),
  title: text("title").notNull(),
  imageUrl: text("image_url"),
  unitId: text("unit_id").notNull(),
  unitTitle: text("unit_title"),
  seasonNumber: integer("season_number"),
  episodeNumber: integer("episode_number"),
  positionSeconds: doublePrecision("position_seconds").notNull().default(0),
  durationSeconds: doublePrecision("duration_seconds").notNull().default(0),
  percentage: doublePrecision("percentage").notNull().default(0),
  completed: boolean("completed").notNull().default(false),
  clientUpdatedAt: timestamp("client_updated_at", { withTimezone: true, mode: "date" }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("media_progress_user_content_unique").on(table.userId, table.mediaType, table.contentId),
  index("media_progress_user_updated_idx").on(table.userId, table.updatedAt),
]);

export const mediaPlaybackSessions = pgTable("media_playback_sessions", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  sessionId: text("session_id").notNull(),
  mediaType: text("media_type").notNull(),
  contentId: text("content_id").notNull(),
  unitId: text("unit_id").notNull(),
  clientStartedAt: timestamp("client_started_at", { withTimezone: true, mode: "date" }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("media_session_user_id_unique").on(table.userId, table.sessionId),
  index("media_session_user_started_idx").on(table.userId, table.clientStartedAt),
]);

export const mediaViewingHistory = pgTable("media_viewing_history", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  mediaType: text("media_type").notNull(),
  contentId: text("content_id").notNull(),
  title: text("title").notNull(),
  imageUrl: text("image_url"),
  unitId: text("unit_id").notNull(),
  unitTitle: text("unit_title"),
  seasonNumber: integer("season_number"),
  episodeNumber: integer("episode_number"),
  positionSeconds: doublePrecision("position_seconds").notNull().default(0),
  durationSeconds: doublePrecision("duration_seconds").notNull().default(0),
  percentage: doublePrecision("percentage").notNull().default(0),
  completed: boolean("completed").notNull().default(false),
  visitCount: integer("visit_count").notNull().default(0),
  clientUpdatedAt: timestamp("client_updated_at", { withTimezone: true, mode: "date" }).notNull(),
  firstViewedAt: timestamp("first_viewed_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  lastViewedAt: timestamp("last_viewed_at", { withTimezone: true, mode: "date" }).notNull().defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: false, mode: "date" }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("media_history_user_unit_unique").on(
    table.userId,
    table.mediaType,
    table.contentId,
    table.unitId
  ),
  index("media_history_user_viewed_idx").on(table.userId, table.lastViewedAt, table.id),
]);
