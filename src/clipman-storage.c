/*
 * clipman-storage.c
 * MATE Clipboard Manager
 * A clipboard history manager for the MATE Desktop
 * Copyright 2025 Kerem Soke
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 * 
 * 
 */

#include "clipman.h"
#include "config.h"

struct _ClipmanStorage
{
  GObject parent;

  sqlite3 *db;
  gchar *db_path;
};

G_DEFINE_TYPE (ClipmanStorage, clipman_storage, G_TYPE_OBJECT)

enum
{
  SIGNAL_ITEM_ADDED,
  SIGNAL_ITEM_REMOVED,
  SIGNAL_CLEARED,
  N_SIGNALS
};

static guint signals[N_SIGNALS];

static void
clipman_storage_finalize (GObject *object)
{
  ClipmanStorage *self = CLIPMAN_STORAGE (object);

  if (self->db)
    sqlite3_close (self->db);
  g_free (self->db_path);

  G_OBJECT_CLASS (clipman_storage_parent_class)->finalize (object);
}

static void
clipman_storage_class_init (ClipmanStorageClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->finalize = clipman_storage_finalize;

  signals[SIGNAL_ITEM_ADDED] = g_signal_new (
      "item-added", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST, 0, NULL,
      NULL, NULL, G_TYPE_NONE, 1, CLIPMAN_TYPE_ITEM);

  signals[SIGNAL_ITEM_REMOVED] = g_signal_new (
      "item-removed", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST, 0, NULL,
      NULL, NULL, G_TYPE_NONE, 1, G_TYPE_INT64);

  signals[SIGNAL_CLEARED]
      = g_signal_new ("cleared", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST,
                      0, NULL, NULL, NULL, G_TYPE_NONE, 0);
}

static gboolean
init_database (ClipmanStorage *self)
{
  const gchar *sql
      = "CREATE TABLE IF NOT EXISTS items ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  type INTEGER NOT NULL,"
        "  source INTEGER NOT NULL,"
        "  checksum TEXT UNIQUE NOT NULL,"
        "  label TEXT NOT NULL,"
        "  text_content TEXT,"
        "  image_data BLOB,"
        "  timestamp INTEGER NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_timestamp ON items(timestamp DESC);"
        "CREATE INDEX IF NOT EXISTS idx_checksum ON items(checksum);";

  char *err = NULL;
  if (sqlite3_exec (self->db, sql, NULL, NULL, &err) != SQLITE_OK)
    {
      g_warning ("Failed to create database tables: %s", err);
      sqlite3_free (err);
      return FALSE;
    }

  return TRUE;
}

static void
clipman_storage_init (ClipmanStorage *self)
{
  gchar *data_dir;
  int rc;

  /* Create data directory */
  data_dir = g_build_filename (g_get_user_data_dir (), "mate-clipman", NULL);
  g_mkdir_with_parents (data_dir, 0755);

  /* Open database */
  self->db_path = g_build_filename (data_dir, "history.db", NULL);
  g_free (data_dir);

  rc = sqlite3_open (self->db_path, &self->db);
  if (rc != SQLITE_OK)
    {
      g_warning ("Cannot open database: %s", sqlite3_errmsg (self->db));
      return;
    }

  /* Enable WAL mode for better performance */
  sqlite3_exec (self->db, "PRAGMA journal_mode=WAL;", NULL, NULL, NULL);
  sqlite3_exec (self->db, "PRAGMA synchronous=NORMAL;", NULL, NULL, NULL);

  init_database (self);
}

ClipmanStorage *
clipman_storage_new (void)
{
  return g_object_new (CLIPMAN_TYPE_STORAGE, NULL);
}

gboolean
clipman_storage_add_item (ClipmanStorage *self, ClipmanItem *item)
{
  sqlite3_stmt *stmt;
  const gchar *sql;
  ClipmanItemType type;
  gint64 id;
  int rc;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (self), FALSE);
  g_return_val_if_fail (CLIPMAN_IS_ITEM (item), FALSE);

  type = clipman_item_get_item_type (item);

  /* First, check if item already exists */
  sql = "SELECT id FROM items WHERE checksum = ?";
  rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
  if (rc == SQLITE_OK)
    {
      sqlite3_bind_text (stmt, 1, clipman_item_get_checksum (item), -1,
                         SQLITE_STATIC);
      if (sqlite3_step (stmt) == SQLITE_ROW)
        {
          /* Item exists - update timestamp to move it to top */
          id = sqlite3_column_int64 (stmt, 0);
          sqlite3_finalize (stmt);

          sql = "UPDATE items SET timestamp = ? WHERE id = ?";
          rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
          if (rc == SQLITE_OK)
            {
              sqlite3_bind_int64 (stmt, 1, g_get_real_time () / 1000000);
              sqlite3_bind_int64 (stmt, 2, id);
              sqlite3_step (stmt);
              sqlite3_finalize (stmt);
            }
          clipman_item_set_id (item, id);
          return TRUE;
        }
      sqlite3_finalize (stmt);
    }

  /* Insert new item */
  sql = "INSERT INTO items (type, source, checksum, label, text_content, "
        "image_data, timestamp) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)";

  rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK)
    {
      g_warning ("Failed to prepare insert statement: %s",
                 sqlite3_errmsg (self->db));
      return FALSE;
    }

  sqlite3_bind_int (stmt, 1, type);
  sqlite3_bind_int (stmt, 2, clipman_item_get_source (item));
  sqlite3_bind_text (stmt, 3, clipman_item_get_checksum (item), -1,
                     SQLITE_STATIC);
  sqlite3_bind_text (stmt, 4, clipman_item_get_label (item), -1,
                     SQLITE_STATIC);

  if (type == CLIPMAN_ITEM_TYPE_TEXT || type == CLIPMAN_ITEM_TYPE_FILES)
    {
      sqlite3_bind_text (stmt, 5, clipman_item_get_text (item), -1,
                         SQLITE_STATIC);
      sqlite3_bind_null (stmt, 6);
    }
  else if (type == CLIPMAN_ITEM_TYPE_IMAGE)
    {
      gchar *buffer = NULL;
      gsize size = 0;
      GdkPixbuf *pixbuf = clipman_item_get_pixbuf (item);

      sqlite3_bind_null (stmt, 5);

      if (gdk_pixbuf_save_to_buffer (pixbuf, &buffer, &size, "png", NULL,
                                     NULL))
        {
          sqlite3_bind_blob (stmt, 6, buffer, size, g_free);
        }
      else
        {
          sqlite3_bind_null (stmt, 6);
        }
    }

  sqlite3_bind_int64 (stmt, 7, g_get_real_time () / 1000000);

  rc = sqlite3_step (stmt);
  sqlite3_finalize (stmt);

  if (rc != SQLITE_DONE)
    {
      g_warning ("Failed to insert item: %s", sqlite3_errmsg (self->db));
      return FALSE;
    }

  id = sqlite3_last_insert_rowid (self->db);
  clipman_item_set_id (item, id);

  g_signal_emit (self, signals[SIGNAL_ITEM_ADDED], 0, item);

  return TRUE;
}

gboolean
clipman_storage_remove_item (ClipmanStorage *self, gint64 id)
{
  sqlite3_stmt *stmt;
  const gchar *sql = "DELETE FROM items WHERE id = ?";
  int rc;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (self), FALSE);

  rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK)
    return FALSE;

  sqlite3_bind_int64 (stmt, 1, id);
  rc = sqlite3_step (stmt);
  sqlite3_finalize (stmt);

  if (rc == SQLITE_DONE)
    {
      g_signal_emit (self, signals[SIGNAL_ITEM_REMOVED], 0, id);
      return TRUE;
    }

  return FALSE;
}

static ClipmanItem *
item_from_row (sqlite3_stmt *stmt)
{
  ClipmanItem *item = NULL;
  ClipmanItemType type;
  ClipmanSource source;
  const gchar *text;
  const void *blob;
  int blob_size;

  type = sqlite3_column_int (stmt, 1);
  source = sqlite3_column_int (stmt, 2);

  switch (type)
    {
    case CLIPMAN_ITEM_TYPE_TEXT:
    case CLIPMAN_ITEM_TYPE_FILES:
      text = (const gchar *)sqlite3_column_text (stmt, 5);
      if (text)
        {
          if (type == CLIPMAN_ITEM_TYPE_TEXT)
            {
              item = clipman_item_new_text (text, source);
            }
          else
            {
              gchar **uris = g_strsplit (text, "\n", -1);
              item = clipman_item_new_files (uris, source);
              g_strfreev (uris);
            }
        }
      break;

    case CLIPMAN_ITEM_TYPE_IMAGE:
      blob = sqlite3_column_blob (stmt, 6);
      blob_size = sqlite3_column_bytes (stmt, 6);
      if (blob && blob_size > 0)
        {
          GInputStream *stream = g_memory_input_stream_new_from_data (
              g_memdup2 (blob, blob_size), blob_size, g_free);
          GdkPixbuf *pixbuf = gdk_pixbuf_new_from_stream (stream, NULL, NULL);
          g_object_unref (stream);
          if (pixbuf)
            {
              item = clipman_item_new_image (pixbuf, source);
              g_object_unref (pixbuf);
            }
        }
      break;
    }

  if (item)
    {
      clipman_item_set_id (item, sqlite3_column_int64 (stmt, 0));
    }

  return item;
}

GList *
clipman_storage_get_items (ClipmanStorage *self, gint limit)
{
  sqlite3_stmt *stmt;
  const gchar *sql = "SELECT id, type, source, checksum, label, text_content, "
                     "image_data, timestamp "
                     "FROM items ORDER BY timestamp DESC LIMIT ?";
  GList *items = NULL;
  int rc;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (self), NULL);

  rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK)
    return NULL;

  sqlite3_bind_int (stmt, 1, limit > 0 ? limit : 100);

  while (sqlite3_step (stmt) == SQLITE_ROW)
    {
      ClipmanItem *item = item_from_row (stmt);
      if (item)
        items = g_list_append (items, item);
    }

  sqlite3_finalize (stmt);

  return items;
}

ClipmanItem *
clipman_storage_get_by_checksum (ClipmanStorage *self, const gchar *checksum)
{
  sqlite3_stmt *stmt;
  const gchar *sql = "SELECT id, type, source, checksum, label, text_content, "
                     "image_data, timestamp "
                     "FROM items WHERE checksum = ?";
  ClipmanItem *item = NULL;
  int rc;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (self), NULL);
  g_return_val_if_fail (checksum != NULL, NULL);

  rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK)
    return NULL;

  sqlite3_bind_text (stmt, 1, checksum, -1, SQLITE_STATIC);

  if (sqlite3_step (stmt) == SQLITE_ROW)
    {
      item = item_from_row (stmt);
    }

  sqlite3_finalize (stmt);

  return item;
}

gboolean
clipman_storage_clear (ClipmanStorage *self)
{
  char *err = NULL;
  int rc;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (self), FALSE);

  rc = sqlite3_exec (self->db, "DELETE FROM items", NULL, NULL, &err);
  if (rc != SQLITE_OK)
    {
      g_warning ("Failed to clear history: %s", err);
      sqlite3_free (err);
      return FALSE;
    }

  g_signal_emit (self, signals[SIGNAL_CLEARED], 0);

  return TRUE;
}

GList *
clipman_storage_search (ClipmanStorage *self, const gchar *query, gint limit)
{
  sqlite3_stmt *stmt;
  const gchar *sql = "SELECT id, type, source, checksum, label, text_content, "
                     "image_data, timestamp "
                     "FROM items WHERE text_content LIKE ? OR label LIKE ? "
                     "ORDER BY timestamp DESC LIMIT ?";
  GList *items = NULL;
  gchar *pattern;
  int rc;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (self), NULL);
  g_return_val_if_fail (query != NULL, NULL);

  rc = sqlite3_prepare_v2 (self->db, sql, -1, &stmt, NULL);
  if (rc != SQLITE_OK)
    return NULL;

  pattern = g_strdup_printf ("%%%s%%", query);
  sqlite3_bind_text (stmt, 1, pattern, -1, SQLITE_TRANSIENT);
  sqlite3_bind_text (stmt, 2, pattern, -1, SQLITE_TRANSIENT);
  sqlite3_bind_int (stmt, 3, limit > 0 ? limit : 100);
  g_free (pattern);

  while (sqlite3_step (stmt) == SQLITE_ROW)
    {
      ClipmanItem *item = item_from_row (stmt);
      if (item)
        items = g_list_append (items, item);
    }

  sqlite3_finalize (stmt);

  return items;
}
