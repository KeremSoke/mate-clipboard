/*
 * clipman-item.c
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
#include <glib/gchecksum.h>

struct _ClipmanItem
{
  GObject parent;

  gint64 id;
  ClipmanItemType type;
  ClipmanSource source;
  gchar *text;
  GdkPixbuf *pixbuf;
  gchar **uris;
  gchar *checksum;
  gchar *label;
  GDateTime *timestamp;
};

G_DEFINE_TYPE (ClipmanItem, clipman_item, G_TYPE_OBJECT)

enum
{
  PROP_0,
  PROP_ID,
  PROP_ITEM_TYPE,
  PROP_SOURCE,
  PROP_TEXT,
  PROP_PIXBUF,
  PROP_CHECKSUM,
  N_PROPS
};

static GParamSpec *properties[N_PROPS];

static void
clipman_item_finalize (GObject *object)
{
  ClipmanItem *self = CLIPMAN_ITEM (object);

  g_free (self->text);
  g_free (self->checksum);
  g_free (self->label);
  g_clear_object (&self->pixbuf);
  g_strfreev (self->uris);
  g_clear_pointer (&self->timestamp, g_date_time_unref);

  G_OBJECT_CLASS (clipman_item_parent_class)->finalize (object);
}

static void
clipman_item_get_property (GObject *object, guint prop_id, GValue *value,
                           GParamSpec *pspec)
{
  ClipmanItem *self = CLIPMAN_ITEM (object);

  switch (prop_id)
    {
    case PROP_ID:
      g_value_set_int64 (value, self->id);
      break;
    case PROP_ITEM_TYPE:
      g_value_set_int (value, self->type);
      break;
    case PROP_SOURCE:
      g_value_set_int (value, self->source);
      break;
    case PROP_TEXT:
      g_value_set_string (value, self->text);
      break;
    case PROP_PIXBUF:
      g_value_set_object (value, self->pixbuf);
      break;
    case PROP_CHECKSUM:
      g_value_set_string (value, self->checksum);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
    }
}

static void
clipman_item_class_init (ClipmanItemClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->finalize = clipman_item_finalize;
  object_class->get_property = clipman_item_get_property;

  properties[PROP_ID] = g_param_spec_int64 (
      "id", "ID", "Database ID", G_MININT64, G_MAXINT64, 0, G_PARAM_READABLE);
  properties[PROP_ITEM_TYPE]
      = g_param_spec_int ("item-type", "Item Type", "Type of clipboard item",
                          0, 2, 0, G_PARAM_READABLE);
  properties[PROP_SOURCE] = g_param_spec_int (
      "source", "Source", "Clipboard source", 0, 1, 0, G_PARAM_READABLE);
  properties[PROP_TEXT] = g_param_spec_string ("text", "Text", "Text content",
                                               NULL, G_PARAM_READABLE);
  properties[PROP_PIXBUF] = g_param_spec_object (
      "pixbuf", "Pixbuf", "Image content", GDK_TYPE_PIXBUF, G_PARAM_READABLE);
  properties[PROP_CHECKSUM] = g_param_spec_string (
      "checksum", "Checksum", "Content checksum", NULL, G_PARAM_READABLE);

  g_object_class_install_properties (object_class, N_PROPS, properties);
}

static void
clipman_item_init (ClipmanItem *self)
{
  self->id = 0;
  self->timestamp = g_date_time_new_now_local ();
}

static gchar *
compute_checksum (const gchar *data, gsize len)
{
  return g_compute_checksum_for_data (G_CHECKSUM_SHA1, (const guchar *)data,
                                      len);
}

static gchar *
create_label (const gchar *text, gsize max_len)
{
  gchar *label;
  gchar *normalized;
  gsize len;

  if (!text)
    return g_strdup ("");

  /* Replace newlines and tabs with spaces */
  normalized = g_strdup (text);
  for (gchar *p = normalized; *p; p++)
    {
      if (*p == '\n' || *p == '\r' || *p == '\t')
        *p = ' ';
    }

  /* Collapse multiple spaces */
  gchar *src = normalized;
  gchar *dst = normalized;
  gboolean prev_space = FALSE;
  while (*src)
    {
      if (*src == ' ')
        {
          if (!prev_space)
            {
              *dst++ = *src;
              prev_space = TRUE;
            }
        }
      else
        {
          *dst++ = *src;
          prev_space = FALSE;
        }
      src++;
    }
  *dst = '\0';

  /* Trim and truncate */
  g_strstrip (normalized);
  len = g_utf8_strlen (normalized, -1);

  if (len > max_len)
    {
      gchar *end = g_utf8_offset_to_pointer (normalized, max_len - 3);
      *end = '\0';
      label = g_strdup_printf ("%s...", normalized);
    }
  else
    {
      label = g_strdup (normalized);
    }

  g_free (normalized);
  return label;
}

ClipmanItem *
clipman_item_new_text (const gchar *text, ClipmanSource source)
{
  ClipmanItem *self;

  g_return_val_if_fail (text != NULL, NULL);

  self = g_object_new (CLIPMAN_TYPE_ITEM, NULL);
  self->type = CLIPMAN_ITEM_TYPE_TEXT;
  self->source = source;
  self->text = g_strdup (text);
  self->checksum = compute_checksum (text, strlen (text));
  self->label = create_label (text, 50);

  return self;
}

ClipmanItem *
clipman_item_new_image (GdkPixbuf *pixbuf, ClipmanSource source)
{
  ClipmanItem *self;
  gchar *buffer = NULL;
  gsize size = 0;
  GError *error = NULL;

  g_return_val_if_fail (GDK_IS_PIXBUF (pixbuf), NULL);

  self = g_object_new (CLIPMAN_TYPE_ITEM, NULL);
  self->type = CLIPMAN_ITEM_TYPE_IMAGE;
  self->source = source;
  self->pixbuf = g_object_ref (pixbuf);

  /* Generate checksum from PNG data */
  if (gdk_pixbuf_save_to_buffer (pixbuf, &buffer, &size, "png", &error, NULL))
    {
      self->checksum = compute_checksum (buffer, size);
      g_free (buffer);
    }
  else
    {
      /* Fallback: use dimensions */
      gchar *dim = g_strdup_printf ("%dx%d", gdk_pixbuf_get_width (pixbuf),
                                    gdk_pixbuf_get_height (pixbuf));
      self->checksum = compute_checksum (dim, strlen (dim));
      g_free (dim);
      g_clear_error (&error);
    }

  self->label
      = g_strdup_printf ("[Image %dx%d]", gdk_pixbuf_get_width (pixbuf),
                         gdk_pixbuf_get_height (pixbuf));

  return self;
}

ClipmanItem *
clipman_item_new_files (gchar **uris, ClipmanSource source)
{
  ClipmanItem *self;
  GString *joined;
  guint count;

  g_return_val_if_fail (uris != NULL, NULL);

  self = g_object_new (CLIPMAN_TYPE_ITEM, NULL);
  self->type = CLIPMAN_ITEM_TYPE_FILES;
  self->source = source;
  self->uris = g_strdupv (uris);

  /* Generate checksum from joined URIs */
  joined = g_string_new (NULL);
  count = 0;
  for (gchar **p = uris; *p; p++)
    {
      if (joined->len > 0)
        g_string_append_c (joined, '\n');
      g_string_append (joined, *p);
      count++;
    }
  self->text = g_string_free (g_string_new (joined->str), FALSE);
  self->checksum = compute_checksum (joined->str, joined->len);

  if (count == 1)
    {
      gchar *basename = g_path_get_basename (uris[0]);
      self->label = g_strdup_printf ("[File: %s]", basename);
      g_free (basename);
    }
  else
    {
      self->label = g_strdup_printf ("[%u files]", count);
    }

  g_string_free (joined, TRUE);

  return self;
}

ClipmanItemType
clipman_item_get_item_type (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), CLIPMAN_ITEM_TYPE_TEXT);
  return self->type;
}

const gchar *
clipman_item_get_text (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), NULL);
  return self->text;
}

GdkPixbuf *
clipman_item_get_pixbuf (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), NULL);
  return self->pixbuf;
}

gchar **
clipman_item_get_uris (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), NULL);
  return self->uris;
}

const gchar *
clipman_item_get_checksum (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), NULL);
  return self->checksum;
}

const gchar *
clipman_item_get_label (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), NULL);
  return self->label;
}

GDateTime *
clipman_item_get_timestamp (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), NULL);
  return self->timestamp;
}

ClipmanSource
clipman_item_get_source (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), CLIPMAN_SOURCE_CLIPBOARD);
  return self->source;
}

gint64
clipman_item_get_id (ClipmanItem *self)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), 0);
  return self->id;
}

void
clipman_item_set_id (ClipmanItem *self, gint64 id)
{
  g_return_if_fail (CLIPMAN_IS_ITEM (self));
  self->id = id;
}

void
clipman_item_to_clipboard (ClipmanItem *self, GtkClipboard *clipboard)
{
  g_return_if_fail (CLIPMAN_IS_ITEM (self));
  g_return_if_fail (GTK_IS_CLIPBOARD (clipboard));

  switch (self->type)
    {
    case CLIPMAN_ITEM_TYPE_TEXT:
      gtk_clipboard_set_text (clipboard, self->text, -1);
      break;
    case CLIPMAN_ITEM_TYPE_IMAGE:
      gtk_clipboard_set_image (clipboard, self->pixbuf);
      break;
    case CLIPMAN_ITEM_TYPE_FILES:
      /* Set as URIs with proper target */
      gtk_clipboard_set_text (clipboard, self->text, -1);
      break;
    }
}

gboolean
clipman_item_equals (ClipmanItem *self, ClipmanItem *other)
{
  g_return_val_if_fail (CLIPMAN_IS_ITEM (self), FALSE);
  g_return_val_if_fail (CLIPMAN_IS_ITEM (other), FALSE);

  return g_strcmp0 (self->checksum, other->checksum) == 0;
}
