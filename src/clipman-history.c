/*
 * clipman-history.c
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

struct _ClipmanHistory
{
  GtkWindow parent;

  ClipmanStorage *storage;
  GSettings *settings;

  GtkWidget *search_entry;
  GtkWidget *list_box;
  GtkWidget *scrolled;
  GtkWidget *empty_label;
  GtkWidget *stack;
};

G_DEFINE_TYPE (ClipmanHistory, clipman_history, GTK_TYPE_WINDOW)

enum
{
  SIGNAL_ITEM_SELECTED,
  SIGNAL_ITEM_DELETED,
  SIGNAL_CLEAR_REQUESTED,
  N_SIGNALS
};

static guint signals[N_SIGNALS];

static void
clipman_history_dispose (GObject *object)
{
  ClipmanHistory *self = CLIPMAN_HISTORY (object);

  g_clear_object (&self->storage);
  g_clear_object (&self->settings);

  G_OBJECT_CLASS (clipman_history_parent_class)->dispose (object);
}

static void
clipman_history_class_init (ClipmanHistoryClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->dispose = clipman_history_dispose;

  signals[SIGNAL_ITEM_SELECTED] = g_signal_new (
      "item-selected", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST, 0, NULL,
      NULL, NULL, G_TYPE_NONE, 1, CLIPMAN_TYPE_ITEM);

  signals[SIGNAL_ITEM_DELETED] = g_signal_new (
      "item-deleted", G_TYPE_FROM_CLASS (klass), G_SIGNAL_RUN_LAST, 0, NULL,
      NULL, NULL, G_TYPE_NONE, 1, G_TYPE_INT64);

  signals[SIGNAL_CLEAR_REQUESTED]
      = g_signal_new ("clear-requested", G_TYPE_FROM_CLASS (klass),
                      G_SIGNAL_RUN_LAST, 0, NULL, NULL, NULL, G_TYPE_NONE, 0);
}

static GtkWidget *
create_item_row (ClipmanHistory *self, ClipmanItem *item)
{
  GtkWidget *row;
  GtkWidget *box;
  GtkWidget *label;
  GtkWidget *delete_btn;
  GtkWidget *image = NULL;
  ClipmanItemType type;

  row = gtk_list_box_row_new ();
  g_object_set_data_full (G_OBJECT (row), "item", g_object_ref (item),
                          g_object_unref);

  box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
  gtk_container_set_border_width (GTK_CONTAINER (box), 6);
  gtk_container_add (GTK_CONTAINER (row), box);

  type = clipman_item_get_item_type (item);

  /* Icon based on type */
  const gchar *icon_name;
  switch (type)
    {
    case CLIPMAN_ITEM_TYPE_TEXT:
      icon_name = "text-x-generic";
      break;
    case CLIPMAN_ITEM_TYPE_IMAGE:
      icon_name = "image-x-generic";
      break;
    case CLIPMAN_ITEM_TYPE_FILES:
      icon_name = "folder";
      break;
    default:
      icon_name = "edit-paste";
    }

  image = gtk_image_new_from_icon_name (icon_name, GTK_ICON_SIZE_MENU);
  gtk_box_pack_start (GTK_BOX (box), image, FALSE, FALSE, 0);

  /* Show thumbnail for images if enabled */
  if (type == CLIPMAN_ITEM_TYPE_IMAGE && self->settings
      && g_settings_get_boolean (self->settings, "show-preview"))
    {
      GdkPixbuf *pixbuf = clipman_item_get_pixbuf (item);
      if (pixbuf)
        {
          gint width = gdk_pixbuf_get_width (pixbuf);
          gint height = gdk_pixbuf_get_height (pixbuf);
          gint max_size = 48;

          if (width > max_size || height > max_size)
            {
              gdouble scale = MIN ((gdouble)max_size / width,
                                   (gdouble)max_size / height);
              GdkPixbuf *scaled = gdk_pixbuf_scale_simple (
                  pixbuf, (gint)(width * scale), (gint)(height * scale),
                  GDK_INTERP_BILINEAR);
              gtk_image_set_from_pixbuf (GTK_IMAGE (image), scaled);
              g_object_unref (scaled);
            }
          else
            {
              gtk_image_set_from_pixbuf (GTK_IMAGE (image), pixbuf);
            }
        }
    }

  /* Label */
  label = gtk_label_new (clipman_item_get_label (item));
  gtk_label_set_xalign (GTK_LABEL (label), 0.0);
  gtk_label_set_ellipsize (GTK_LABEL (label), PANGO_ELLIPSIZE_END);
  gtk_widget_set_hexpand (label, TRUE);
  gtk_box_pack_start (GTK_BOX (box), label, TRUE, TRUE, 0);

  /* Delete button */
  delete_btn = gtk_button_new_from_icon_name ("edit-delete-symbolic",
                                              GTK_ICON_SIZE_BUTTON);
  gtk_button_set_relief (GTK_BUTTON (delete_btn), GTK_RELIEF_NONE);
  gtk_widget_set_tooltip_text (delete_btn, "Delete this item");
  g_object_set_data (G_OBJECT (delete_btn), "item-id",
                     GINT_TO_POINTER ((gint)clipman_item_get_id (item)));
  gtk_box_pack_end (GTK_BOX (box), delete_btn, FALSE, FALSE, 0);

  gtk_widget_show_all (row);

  return row;
}

static void
on_row_activated (GtkListBox *box, GtkListBoxRow *row, gpointer user_data)
{
  ClipmanHistory *self = CLIPMAN_HISTORY (user_data);
  ClipmanItem *item;

  item = g_object_get_data (G_OBJECT (row), "item");
  if (item)
    {
      g_signal_emit (self, signals[SIGNAL_ITEM_SELECTED], 0, item);
      gtk_widget_hide (GTK_WIDGET (self));
    }
}

static void
on_delete_clicked (GtkButton *button, gpointer user_data)
{
  ClipmanHistory *self = CLIPMAN_HISTORY (user_data);
  gint64 id
      = GPOINTER_TO_INT (g_object_get_data (G_OBJECT (button), "item-id"));

  g_signal_emit (self, signals[SIGNAL_ITEM_DELETED], 0, id);
}

static void
on_clear_btn_clicked (ClipmanHistory *self)
{
  g_signal_emit (self, signals[SIGNAL_CLEAR_REQUESTED], 0);
}

static gboolean
on_key_press (GtkWidget *widget, GdkEventKey *event, gpointer user_data)
{
  ClipmanHistory *self = CLIPMAN_HISTORY (user_data);

  if (event->keyval == GDK_KEY_Escape)
    {
      gtk_widget_hide (widget);
      return TRUE;
    }

  /* Focus search on typing */
  if (!gtk_widget_has_focus (self->search_entry)
      && event->keyval >= GDK_KEY_space && event->keyval <= GDK_KEY_asciitilde)
    {
      gtk_widget_grab_focus (self->search_entry);
    }

  return FALSE;
}

static void
on_search_changed (GtkSearchEntry *entry, gpointer user_data)
{
  ClipmanHistory *self = CLIPMAN_HISTORY (user_data);
  const gchar *text;
  GList *items, *l;
  gint limit;

  text = gtk_entry_get_text (GTK_ENTRY (entry));

  /* Clear current items */
  gtk_container_foreach (GTK_CONTAINER (self->list_box),
                         (GtkCallback)gtk_widget_destroy, NULL);

  limit = self->settings ? g_settings_get_int (self->settings, "history-size")
                         : 50;

  if (text && strlen (text) > 0)
    {
      items = clipman_storage_search (self->storage, text, limit);
    }
  else
    {
      items = clipman_storage_get_items (self->storage, limit);
    }

  if (!items || g_list_length (items) == 0)
    {
      gtk_stack_set_visible_child_name (GTK_STACK (self->stack), "empty");
      if (items)
        g_list_free (items);
      return;
    }

  gtk_stack_set_visible_child_name (GTK_STACK (self->stack), "list");

  for (l = items; l; l = l->next)
    {
      ClipmanItem *item = l->data;
      GtkWidget *row = create_item_row (self, item);

      /* Connect delete button */
      GtkWidget *box = gtk_bin_get_child (GTK_BIN (row));
      GList *children = gtk_container_get_children (GTK_CONTAINER (box));
      for (GList *c = children; c; c = c->next)
        {
          if (GTK_IS_BUTTON (c->data))
            {
              g_signal_connect (c->data, "clicked",
                                G_CALLBACK (on_delete_clicked), self);
            }
        }
      g_list_free (children);

      gtk_list_box_insert (GTK_LIST_BOX (self->list_box), row, -1);
    }

  g_list_free_full (items, g_object_unref);
}

static gboolean
on_focus_out (GtkWidget *widget, GdkEventFocus *event, gpointer user_data)
{
  /* Hide on focus loss */
  gtk_widget_hide (widget);
  return FALSE;
}

static void
clipman_history_init (ClipmanHistory *self)
{
  GtkWidget *vbox;
  GtkWidget *header;
  GtkWidget *clear_btn;

  gtk_window_set_title (GTK_WINDOW (self), "Clipboard History");
  gtk_window_set_default_size (GTK_WINDOW (self), 400, 450);
  gtk_window_set_type_hint (GTK_WINDOW (self),
                            GDK_WINDOW_TYPE_HINT_POPUP_MENU);
  gtk_window_set_skip_taskbar_hint (GTK_WINDOW (self), TRUE);
  gtk_window_set_skip_pager_hint (GTK_WINDOW (self), TRUE);
  gtk_window_set_decorated (GTK_WINDOW (self), FALSE);
  gtk_container_set_border_width (GTK_CONTAINER (self), 1);

  /* Add frame for border */
  GtkWidget *frame = gtk_frame_new (NULL);
  gtk_frame_set_shadow_type (GTK_FRAME (frame), GTK_SHADOW_OUT);
  gtk_container_add (GTK_CONTAINER (self), frame);

  vbox = gtk_box_new (GTK_ORIENTATION_VERTICAL, 0);
  gtk_container_add (GTK_CONTAINER (frame), vbox);

  /* Header with search and clear */
  header = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
  gtk_container_set_border_width (GTK_CONTAINER (header), 6);
  gtk_box_pack_start (GTK_BOX (vbox), header, FALSE, FALSE, 0);

  self->search_entry = gtk_search_entry_new ();
  gtk_entry_set_placeholder_text (GTK_ENTRY (self->search_entry),
                                  "Search history...");
  gtk_widget_set_hexpand (self->search_entry, TRUE);
  gtk_box_pack_start (GTK_BOX (header), self->search_entry, TRUE, TRUE, 0);

  clear_btn = gtk_button_new_from_icon_name ("edit-clear-all-symbolic",
                                             GTK_ICON_SIZE_BUTTON);
  gtk_widget_set_tooltip_text (clear_btn, "Clear all history");
  gtk_box_pack_end (GTK_BOX (header), clear_btn, FALSE, FALSE, 0);

  /* Separator */
  gtk_box_pack_start (GTK_BOX (vbox),
                      gtk_separator_new (GTK_ORIENTATION_HORIZONTAL), FALSE,
                      FALSE, 0);

  /* Stack for list/empty views */
  self->stack = gtk_stack_new ();
  gtk_box_pack_start (GTK_BOX (vbox), self->stack, TRUE, TRUE, 0);

  /* Scrolled window with list */
  self->scrolled = gtk_scrolled_window_new (NULL, NULL);
  gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (self->scrolled),
                                  GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
  gtk_stack_add_named (GTK_STACK (self->stack), self->scrolled, "list");

  self->list_box = gtk_list_box_new ();
  gtk_list_box_set_selection_mode (GTK_LIST_BOX (self->list_box),
                                   GTK_SELECTION_SINGLE);
  gtk_list_box_set_activate_on_single_click (GTK_LIST_BOX (self->list_box),
                                             TRUE);
  gtk_container_add (GTK_CONTAINER (self->scrolled), self->list_box);

  /* Empty state */
  self->empty_label = gtk_label_new ("No clipboard history");
  gtk_widget_set_sensitive (self->empty_label, FALSE);
  gtk_stack_add_named (GTK_STACK (self->stack), self->empty_label, "empty");

  /* Connect signals */
  g_signal_connect (self->list_box, "row-activated",
                    G_CALLBACK (on_row_activated), self);
  g_signal_connect (self->search_entry, "search-changed",
                    G_CALLBACK (on_search_changed), self);
  g_signal_connect (self, "key-press-event", G_CALLBACK (on_key_press), self);
  g_signal_connect (self, "focus-out-event", G_CALLBACK (on_focus_out), self);
  g_signal_connect_swapped (clear_btn, "clicked",
                            G_CALLBACK (on_clear_btn_clicked), self);

  gtk_widget_show_all (frame);
}

ClipmanHistory *
clipman_history_new (ClipmanStorage *storage, GSettings *settings)
{
  ClipmanHistory *self;

  g_return_val_if_fail (CLIPMAN_IS_STORAGE (storage), NULL);

  self = g_object_new (CLIPMAN_TYPE_HISTORY, NULL);
  self->storage = g_object_ref (storage);

  if (settings)
    self->settings = g_object_ref (settings);

  return self;
}

void
clipman_history_show_popup (ClipmanHistory *self)
{
  GdkDisplay *display;
  GdkSeat *seat;
  GdkDevice *pointer;
  gint x, y;

  g_return_if_fail (CLIPMAN_IS_HISTORY (self));

  /* Refresh content */
  clipman_history_refresh (self);

  /* Position near mouse cursor */
  display = gdk_display_get_default ();
  seat = gdk_display_get_default_seat (display);
  pointer = gdk_seat_get_pointer (seat);
  gdk_device_get_position (pointer, NULL, &x, &y);

  /* Adjust position to keep on screen */
  GdkMonitor *monitor = gdk_display_get_monitor_at_point (display, x, y);
  GdkRectangle geom;
  gdk_monitor_get_geometry (monitor, &geom);

  gint width, height;
  gtk_window_get_size (GTK_WINDOW (self), &width, &height);

  if (x + width > geom.x + geom.width)
    x = geom.x + geom.width - width;
  if (y + height > geom.y + geom.height)
    y = geom.y + geom.height - height;

  gtk_window_move (GTK_WINDOW (self), x, y);
  gtk_widget_show (GTK_WIDGET (self));
  gtk_window_present (GTK_WINDOW (self));

  /* Focus search entry */
  gtk_widget_grab_focus (self->search_entry);
}

void
clipman_history_refresh (ClipmanHistory *self)
{
  g_return_if_fail (CLIPMAN_IS_HISTORY (self));

  /* Clear search and reload */
  gtk_entry_set_text (GTK_ENTRY (self->search_entry), "");
  on_search_changed (GTK_SEARCH_ENTRY (self->search_entry), self);
}
