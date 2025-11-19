/*
 * clipman-applet.c
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

#include "config.h"

#ifdef HAVE_MATE_PANEL

#include "clipman.h"
#include <mate-panel-applet.h>

typedef struct
{
  MatePanelApplet *applet;
  GSettings *settings;
  ClipmanStorage *storage;
  ClipmanManager *manager;
  ClipmanHistory *history;
  ClipmanPreferences *preferences;

  GtkWidget *button;
  GtkWidget *image;
} ClipmanAppletData;

static void
on_item_received (ClipmanManager *manager, ClipmanItem *item,
                  gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  clipman_storage_add_item (data->storage, item);

  /* Sync selections if enabled */
  if (g_settings_get_boolean (data->settings, "sync-selections"))
    {
      GtkClipboard *clipboard = gtk_clipboard_get (GDK_SELECTION_CLIPBOARD);
      GtkClipboard *primary = gtk_clipboard_get (GDK_SELECTION_PRIMARY);
      ClipmanSource source = clipman_item_get_source (item);

      if (source == CLIPMAN_SOURCE_CLIPBOARD)
        {
          clipman_item_to_clipboard (item, primary);
        }
      else
        {
          clipman_item_to_clipboard (item, clipboard);
        }
    }
}

static void
on_clipboard_empty (ClipmanManager *manager, gint source, gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  if (!g_settings_get_boolean (data->settings, "keep-content"))
    return;

  GList *items = clipman_storage_get_items (data->storage, 1);
  if (items)
    {
      ClipmanItem *item = items->data;
      GtkClipboard *clipboard;

      if (source == CLIPMAN_SOURCE_PRIMARY)
        clipboard = gtk_clipboard_get (GDK_SELECTION_PRIMARY);
      else
        clipboard = gtk_clipboard_get (GDK_SELECTION_CLIPBOARD);

      clipman_item_to_clipboard (item, clipboard);
      g_list_free_full (items, g_object_unref);
    }
}

static void
on_item_selected (ClipmanHistory *history, ClipmanItem *item,
                  gpointer user_data)
{
  ClipmanAppletData *data = user_data;
  GtkClipboard *clipboard = gtk_clipboard_get (GDK_SELECTION_CLIPBOARD);

  clipman_item_to_clipboard (item, clipboard);
  clipman_storage_add_item (data->storage, item);
}

static void
on_item_deleted (ClipmanHistory *history, gint64 id, gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  clipman_storage_remove_item (data->storage, id);
  clipman_history_refresh (data->history);
}

static void
on_clear_requested (ClipmanHistory *history, gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  if (g_settings_get_boolean (data->settings, "confirm-clear"))
    {
      GtkWidget *dialog = gtk_message_dialog_new (
          NULL, GTK_DIALOG_MODAL, GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO,
          "Clear all clipboard history?");
      gtk_message_dialog_format_secondary_text (
          GTK_MESSAGE_DIALOG (dialog), "This action cannot be undone.");

      gint response = gtk_dialog_run (GTK_DIALOG (dialog));
      gtk_widget_destroy (dialog);

      if (response != GTK_RESPONSE_YES)
        return;
    }

  clipman_storage_clear (data->storage);
  clipman_history_refresh (data->history);
}

static void
on_button_clicked (GtkButton *button, gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  clipman_history_show_popup (data->history);
}

static void
show_preferences (GtkAction *action, gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  if (!data->preferences)
    data->preferences = clipman_preferences_new (NULL, data->settings);

  gtk_window_present (GTK_WINDOW (data->preferences));
}

static void
clear_history (GtkAction *action, gpointer user_data)
{
  ClipmanAppletData *data = user_data;

  on_clear_requested (data->history, data);
}

static void
show_about (GtkAction *action, gpointer user_data)
{
  const gchar *authors[] = { "MATE Clipboard Manager Authors", NULL };

  gtk_show_about_dialog (NULL, "program-name", "MATE Clipboard Manager",
                         "version", PACKAGE_VERSION, "comments",
                         "A clipboard history manager for MATE Desktop",
                         "copyright", "Copyright \xc2\xa9 2024",
                         "license-type", GTK_LICENSE_GPL_3_0, "authors",
                         authors, "logo-icon-name", "edit-paste", NULL);
}

static const GtkActionEntry applet_menu_actions[] = {
  { "Preferences", "preferences-system", "_Preferences", NULL, NULL,
    G_CALLBACK (show_preferences) },
  { "Clear", "edit-clear-all", "_Clear History", NULL, NULL,
    G_CALLBACK (clear_history) },
  { "About", "help-about", "_About", NULL, NULL, G_CALLBACK (show_about) },
};

static const gchar *applet_menu_xml
    = "<menuitem name=\"Preferences\" action=\"Preferences\"/>"
      "<menuitem name=\"Clear\" action=\"Clear\"/>"
      "<separator/>"
      "<menuitem name=\"About\" action=\"About\"/>";

static void
applet_data_free (ClipmanAppletData *data)
{
  if (data->manager)
    {
      clipman_manager_stop (data->manager);
      g_object_unref (data->manager);
    }

  g_clear_object (&data->storage);
  g_clear_object (&data->settings);

  if (data->history)
    gtk_widget_destroy (GTK_WIDGET (data->history));
  if (data->preferences)
    gtk_widget_destroy (GTK_WIDGET (data->preferences));

  g_free (data);
}

static void
on_applet_destroy (GtkWidget *widget, gpointer user_data)
{
  ClipmanAppletData *data = user_data;
  applet_data_free (data);
}

static gboolean
clipman_applet_fill (MatePanelApplet *applet)
{
  ClipmanAppletData *data;
  GtkActionGroup *action_group;

  /* Set up applet */
  mate_panel_applet_set_flags (applet, MATE_PANEL_APPLET_EXPAND_MINOR
                                           | MATE_PANEL_APPLET_HAS_HANDLE);
  mate_panel_applet_set_background_widget (applet, GTK_WIDGET (applet));

  /* Create data structure */
  data = g_new0 (ClipmanAppletData, 1);
  data->applet = applet;

  /* Create button */
  data->button = gtk_button_new ();
  gtk_button_set_relief (GTK_BUTTON (data->button), GTK_RELIEF_NONE);
  gtk_widget_set_tooltip_text (data->button, "Clipboard History");

  data->image
      = gtk_image_new_from_icon_name ("edit-paste", GTK_ICON_SIZE_BUTTON);
  gtk_container_add (GTK_CONTAINER (data->button), data->image);

  gtk_container_add (GTK_CONTAINER (applet), data->button);
  gtk_widget_show_all (GTK_WIDGET (applet));

  /* Initialize components */
  data->settings = g_settings_new ("org.mate.clipman");
  data->storage = clipman_storage_new ();
  data->manager = clipman_manager_new ();
  clipman_manager_set_settings (data->manager, data->settings);

  g_signal_connect (data->manager, "item-received",
                    G_CALLBACK (on_item_received), data);
  g_signal_connect (data->manager, "clipboard-empty",
                    G_CALLBACK (on_clipboard_empty), data);

  data->history = clipman_history_new (data->storage, data->settings);

  g_signal_connect (data->history, "item-selected",
                    G_CALLBACK (on_item_selected), data);
  g_signal_connect (data->history, "item-deleted",
                    G_CALLBACK (on_item_deleted), data);
  g_signal_connect (data->history, "clear-requested",
                    G_CALLBACK (on_clear_requested), data);

  g_signal_connect (data->button, "clicked", G_CALLBACK (on_button_clicked),
                    data);

  /* Set up menu */
  action_group = gtk_action_group_new ("ClipmanAppletActions");
  gtk_action_group_add_actions (action_group, applet_menu_actions,
                                G_N_ELEMENTS (applet_menu_actions), data);

  mate_panel_applet_setup_menu (applet, applet_menu_xml, action_group);

  g_object_unref (action_group);

  /* Start monitoring */
  clipman_manager_start (data->manager);

  /* Clean up on destroy */
  g_signal_connect (applet, "destroy", G_CALLBACK (on_applet_destroy), data);

  return TRUE;
}

static gboolean
clipman_applet_factory (MatePanelApplet *applet, const gchar *iid,
                        gpointer user_data)
{
  if (g_strcmp0 (iid, "ClipmanApplet") != 0)
    return FALSE;

  return clipman_applet_fill (applet);
}

MATE_PANEL_APPLET_OUT_PROCESS_FACTORY ("ClipmanAppletFactory",
                                       PANEL_TYPE_APPLET, "ClipmanApplet",
                                       clipman_applet_factory, NULL)

#endif /* HAVE_MATE_PANEL */
