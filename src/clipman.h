/*
 * clipman.h
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

#ifndef __CLIPMAN_H__
#define __CLIPMAN_H__

#include <gdk/gdkx.h>
#include <gio/gio.h>
#include <glib.h>
#include <gtk/gtk.h>
#include <sqlite3.h>
#include <string.h>
#include <time.h>

G_BEGIN_DECLS

/* Forward declarations */
typedef struct _ClipmanApp ClipmanApp;
typedef struct _ClipmanItem ClipmanItem;
typedef struct _ClipmanManager ClipmanManager;
typedef struct _ClipmanStorage ClipmanStorage;
typedef struct _ClipmanHistory ClipmanHistory;
typedef struct _ClipmanPreferences ClipmanPreferences;

/* Item types */
typedef enum
{
  CLIPMAN_ITEM_TYPE_TEXT,
  CLIPMAN_ITEM_TYPE_IMAGE,
  CLIPMAN_ITEM_TYPE_FILES
} ClipmanItemType;

/* Clipboard source */
typedef enum
{
  CLIPMAN_SOURCE_CLIPBOARD,
  CLIPMAN_SOURCE_PRIMARY
} ClipmanSource;

/*
 * ClipmanItem - Represents a single clipboard entry
 */
#define CLIPMAN_TYPE_ITEM (clipman_item_get_type ())
G_DECLARE_FINAL_TYPE (ClipmanItem, clipman_item, CLIPMAN, ITEM, GObject)

ClipmanItem *clipman_item_new_text (const gchar *text, ClipmanSource source);
ClipmanItem *clipman_item_new_image (GdkPixbuf *pixbuf, ClipmanSource source);
ClipmanItem *clipman_item_new_files (gchar **uris, ClipmanSource source);

ClipmanItemType clipman_item_get_item_type (ClipmanItem *self);
const gchar *clipman_item_get_text (ClipmanItem *self);
GdkPixbuf *clipman_item_get_pixbuf (ClipmanItem *self);
gchar **clipman_item_get_uris (ClipmanItem *self);
const gchar *clipman_item_get_checksum (ClipmanItem *self);
const gchar *clipman_item_get_label (ClipmanItem *self);
GDateTime *clipman_item_get_timestamp (ClipmanItem *self);
ClipmanSource clipman_item_get_source (ClipmanItem *self);
gint64 clipman_item_get_id (ClipmanItem *self);
void clipman_item_set_id (ClipmanItem *self, gint64 id);
void clipman_item_to_clipboard (ClipmanItem *self, GtkClipboard *clipboard);
gboolean clipman_item_equals (ClipmanItem *self, ClipmanItem *other);

/*
 * ClipmanStorage - SQLite database storage
 */
#define CLIPMAN_TYPE_STORAGE (clipman_storage_get_type ())
G_DECLARE_FINAL_TYPE (ClipmanStorage, clipman_storage, CLIPMAN, STORAGE,
                      GObject)

ClipmanStorage *clipman_storage_new (void);
gboolean clipman_storage_add_item (ClipmanStorage *self, ClipmanItem *item);
gboolean clipman_storage_remove_item (ClipmanStorage *self, gint64 id);
GList *clipman_storage_get_items (ClipmanStorage *self, gint limit);
ClipmanItem *clipman_storage_get_by_checksum (ClipmanStorage *self,
                                              const gchar *checksum);
gboolean clipman_storage_clear (ClipmanStorage *self);
GList *clipman_storage_search (ClipmanStorage *self, const gchar *query,
                               gint limit);

/*
 * ClipmanManager - Monitors clipboard changes
 */
#define CLIPMAN_TYPE_MANAGER (clipman_manager_get_type ())
G_DECLARE_FINAL_TYPE (ClipmanManager, clipman_manager, CLIPMAN, MANAGER,
                      GObject)

ClipmanManager *clipman_manager_new (void);
void clipman_manager_set_settings (ClipmanManager *self, GSettings *settings);
void clipman_manager_start (ClipmanManager *self);
void clipman_manager_stop (ClipmanManager *self);

/*
 * ClipmanHistory - History popup window
 */
#define CLIPMAN_TYPE_HISTORY (clipman_history_get_type ())
G_DECLARE_FINAL_TYPE (ClipmanHistory, clipman_history, CLIPMAN, HISTORY,
                      GtkWindow)

ClipmanHistory *clipman_history_new (ClipmanStorage *storage,
                                     GSettings *settings);
void clipman_history_show_popup (ClipmanHistory *self);
void clipman_history_refresh (ClipmanHistory *self);

/*
 * ClipmanPreferences - Preferences dialog
 */
#define CLIPMAN_TYPE_PREFERENCES (clipman_preferences_get_type ())
G_DECLARE_FINAL_TYPE (ClipmanPreferences, clipman_preferences, CLIPMAN,
                      PREFERENCES, GtkDialog)

ClipmanPreferences *clipman_preferences_new (GtkWindow *parent,
                                             GSettings *settings);

/*
 * ClipmanApp - Main application
 */
#define CLIPMAN_TYPE_APP (clipman_app_get_type ())
G_DECLARE_FINAL_TYPE (ClipmanApp, clipman_app, CLIPMAN, APP, GtkApplication)

ClipmanApp *clipman_app_new (void);

G_END_DECLS

#endif /* __CLIPMAN_H__ */
