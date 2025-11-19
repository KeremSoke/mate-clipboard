/*
 * clipman-manager.c
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
#include <X11/Xlib.h>

struct _ClipmanManager
{
  GObject parent;

  GtkClipboard *clipboard;
  GtkClipboard *primary;
  GSettings *settings;

  guint check_timeout_id;
  gchar *last_clipboard_checksum;
  gchar *last_primary_checksum;

  gboolean running;
  gboolean ignore_next;
};

G_DEFINE_TYPE (ClipmanManager, clipman_manager, G_TYPE_OBJECT)

enum
{
  SIGNAL_ITEM_RECEIVED,
  SIGNAL_CLIPBOARD_EMPTY,
  N_SIGNALS
};

static guint signals[N_SIGNALS];

static void
clipman_manager_finalize (GObject *object)
{
  ClipmanManager *self = CLIPMAN_MANAGER (object);

  if (self->check_timeout_id > 0)
    g_source_remove (self->check_timeout_id);

  g_free (self->last_clipboard_checksum);
  g_free (self->last_primary_checksum);
  g_clear_object (&self->settings);

  G_OBJECT_CLASS (clipman_manager_parent_class)->finalize (object);
}

static void
clipman_manager_class_init (ClipmanManagerClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->finalize = clipman_manager_finalize;

  signals[SIGNAL_ITEM_RECEIVED] = g_signal_new (
      "item-received", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST, 0, NULL,
      NULL, NULL, G_TYPE_NONE, 1, CLIPMAN_TYPE_ITEM);

  signals[SIGNAL_CLIPBOARD_EMPTY] = g_signal_new (
      "clipboard-empty", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST, 0, NULL,
      NULL, NULL, G_TYPE_NONE, 1, G_TYPE_INT);
}

static void
clipman_manager_init (ClipmanManager *self)
{
  GdkDisplay *display = gdk_display_get_default ();

  self->clipboard
      = gtk_clipboard_get_for_display (display, GDK_SELECTION_CLIPBOARD);
  self->primary
      = gtk_clipboard_get_for_display (display, GDK_SELECTION_PRIMARY);
  self->running = FALSE;
  self->ignore_next = FALSE;
}

ClipmanManager *
clipman_manager_new (void)
{
  return g_object_new (CLIPMAN_TYPE_MANAGER, NULL);
}

void
clipman_manager_set_settings (ClipmanManager *self, GSettings *settings)
{
  g_return_if_fail (CLIPMAN_IS_MANAGER (self));
  g_return_if_fail (G_IS_SETTINGS (settings));

  g_clear_object (&self->settings);
  self->settings = g_object_ref (settings);
}

static void
process_text (ClipmanManager *self, GtkClipboard *clipboard, const gchar *text)
{
  ClipmanItem *item;
  ClipmanSource source;
  const gchar *checksum;
  gchar **last_checksum;
  gchar *exclude_pattern;

  if (!text || strlen (text) == 0)
    return;

  source = (clipboard == self->primary) ? CLIPMAN_SOURCE_PRIMARY
                                        : CLIPMAN_SOURCE_CLIPBOARD;
  last_checksum = (source == CLIPMAN_SOURCE_PRIMARY)
                      ? &self->last_primary_checksum
                      : &self->last_clipboard_checksum;

  /* Check exclude pattern */
  if (self->settings)
    {
      exclude_pattern
          = g_settings_get_string (self->settings, "exclude-pattern");
      if (exclude_pattern && strlen (exclude_pattern) > 0)
        {
          GRegex *regex = g_regex_new (exclude_pattern, 0, 0, NULL);
          if (regex)
            {
              if (g_regex_match (regex, text, 0, NULL))
                {
                  g_regex_unref (regex);
                  g_free (exclude_pattern);
                  return;
                }
              g_regex_unref (regex);
            }
        }
      g_free (exclude_pattern);
    }

  item = clipman_item_new_text (text, source);
  checksum = clipman_item_get_checksum (item);

  /* Check for duplicates */
  if (g_strcmp0 (checksum, *last_checksum) == 0)
    {
      g_object_unref (item);
      return;
    }

  g_free (*last_checksum);
  *last_checksum = g_strdup (checksum);

  g_signal_emit (self, signals[SIGNAL_ITEM_RECEIVED], 0, item);
  g_object_unref (item);
}

static void
process_image (ClipmanManager *self, GtkClipboard *clipboard,
               GdkPixbuf *pixbuf)
{
  ClipmanItem *item;
  ClipmanSource source;

  if (!pixbuf)
    return;

  if (self->settings
      && !g_settings_get_boolean (self->settings, "save-images"))
    return;

  source = (clipboard == self->primary) ? CLIPMAN_SOURCE_PRIMARY
                                        : CLIPMAN_SOURCE_CLIPBOARD;

  item = clipman_item_new_image (pixbuf, source);
  g_signal_emit (self, signals[SIGNAL_ITEM_RECEIVED], 0, item);
  g_object_unref (item);
}

static void
process_uris (ClipmanManager *self, GtkClipboard *clipboard, gchar **uris)
{
  ClipmanItem *item;
  ClipmanSource source;

  if (!uris || !uris[0])
    return;

  if (self->settings && !g_settings_get_boolean (self->settings, "save-files"))
    return;

  source = (clipboard == self->primary) ? CLIPMAN_SOURCE_PRIMARY
                                        : CLIPMAN_SOURCE_CLIPBOARD;

  item = clipman_item_new_files (uris, source);
  g_signal_emit (self, signals[SIGNAL_ITEM_RECEIVED], 0, item);
  g_object_unref (item);
}

static void
check_clipboard_content (ClipmanManager *self, GtkClipboard *clipboard)
{
  gchar **uris;

  /* First check for URIs (files) */
  uris = gtk_clipboard_wait_for_uris (clipboard);
  if (uris && uris[0])
    {
      process_uris (self, clipboard, uris);
      g_strfreev (uris);
      return;
    }
  g_strfreev (uris);

  /* Then check for images */
  if (gtk_clipboard_wait_is_image_available (clipboard))
    {
      GdkPixbuf *pixbuf = gtk_clipboard_wait_for_image (clipboard);
      if (pixbuf)
        {
          process_image (self, clipboard, pixbuf);
          g_object_unref (pixbuf);
          return;
        }
    }

  /* Finally check for text */
  if (gtk_clipboard_wait_is_text_available (clipboard))
    {
      gchar *text = gtk_clipboard_wait_for_text (clipboard);
      if (text)
        {
          process_text (self, clipboard, text);
          g_free (text);
          return;
        }
    }

  /* Clipboard is empty */
  ClipmanSource source = (clipboard == self->primary)
                             ? CLIPMAN_SOURCE_PRIMARY
                             : CLIPMAN_SOURCE_CLIPBOARD;
  g_signal_emit (self, signals[SIGNAL_CLIPBOARD_EMPTY], 0, source);
}

static void
on_owner_change (GtkClipboard *clipboard, GdkEvent *event, gpointer user_data)
{
  ClipmanManager *self = CLIPMAN_MANAGER (user_data);

  if (!self->running)
    return;

  /* Check for primary selection only if enabled */
  if (clipboard == self->primary)
    {
      if (!self->settings
          || !g_settings_get_boolean (self->settings, "use-primary-selection"))
        return;
    }

  check_clipboard_content (self, clipboard);
}

void
clipman_manager_start (ClipmanManager *self)
{
  g_return_if_fail (CLIPMAN_IS_MANAGER (self));

  if (self->running)
    return;

  self->running = TRUE;

  g_signal_connect (self->clipboard, "owner-change",
                    G_CALLBACK (on_owner_change), self);
  g_signal_connect (self->primary, "owner-change",
                    G_CALLBACK (on_owner_change), self);

  /* Initial check */
  check_clipboard_content (self, self->clipboard);
}

void
clipman_manager_stop (ClipmanManager *self)
{
  g_return_if_fail (CLIPMAN_IS_MANAGER (self));

  if (!self->running)
    return;

  self->running = FALSE;

  g_signal_handlers_disconnect_by_func (self->clipboard, on_owner_change,
                                        self);
  g_signal_handlers_disconnect_by_func (self->primary, on_owner_change, self);
}
