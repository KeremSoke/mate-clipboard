/*
 * clipman-app.c\
 *
 * MATE Clipboard Manager
 * A clipboard history manager for the MATE Desktop
 * 
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

struct _ClipmanApp
{
  GtkApplication parent;

  GSettings *settings;
  ClipmanStorage *storage;
  ClipmanManager *manager;
  ClipmanHistory *history;
  ClipmanPreferences *preferences;

  GtkStatusIcon *status_icon;
  GtkWidget *menu;

  gboolean start_hidden;
};

G_DEFINE_TYPE (ClipmanApp, clipman_app, GTK_TYPE_APPLICATION)

static void
on_item_received (ClipmanManager *manager, ClipmanItem *item,
                  gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  clipman_storage_add_item (self->storage, item);

  /* Sync selections if enabled */
  if (g_settings_get_boolean (self->settings, "sync-selections"))
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
  ClipmanApp *self = CLIPMAN_APP (user_data);

  if (!g_settings_get_boolean (self->settings, "keep-content"))
    return;

  /* Restore last item to clipboard */
  GList *items = clipman_storage_get_items (self->storage, 1);
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
  ClipmanApp *self = CLIPMAN_APP (user_data);
  GtkClipboard *clipboard = gtk_clipboard_get (GDK_SELECTION_CLIPBOARD);

  clipman_item_to_clipboard (item, clipboard);

  /* Update timestamp in storage */
  clipman_storage_add_item (self->storage, item);
}

static void
on_item_deleted (ClipmanHistory *history, gint64 id, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  clipman_storage_remove_item (self->storage, id);
  clipman_history_refresh (self->history);
}

static void
on_clear_requested (ClipmanHistory *history, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  if (g_settings_get_boolean (self->settings, "confirm-clear"))
    {
      GtkWidget *dialog = gtk_message_dialog_new (
          GTK_WINDOW (history),
          GTK_DIALOG_MODAL | GTK_DIALOG_DESTROY_WITH_PARENT,
          GTK_MESSAGE_QUESTION, GTK_BUTTONS_YES_NO,
          _ ("Clear all clipboard history?"));
      gtk_message_dialog_format_secondary_text (
          GTK_MESSAGE_DIALOG (dialog), _ ("This action cannot be undone."));

      gint response = gtk_dialog_run (GTK_DIALOG (dialog));
      gtk_widget_destroy (dialog);

      if (response != GTK_RESPONSE_YES)
        return;
    }

  clipman_storage_clear (self->storage);
  clipman_history_refresh (self->history);
}

static void
show_history_action (GSimpleAction *action, GVariant *parameter,
                     gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  clipman_history_show_popup (self->history);
}

static void
show_preferences_action (GSimpleAction *action, GVariant *parameter,
                         gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  if (!self->preferences)
    self->preferences = clipman_preferences_new (NULL, self->settings);

  gtk_window_present (GTK_WINDOW (self->preferences));
}

static void
clear_history_action (GSimpleAction *action, GVariant *parameter,
                      gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  on_clear_requested (self->history, self);
}

static void
quit_action (GSimpleAction *action, GVariant *parameter, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  g_application_quit (G_APPLICATION (self));
}

static void
on_status_icon_activate (GtkStatusIcon *icon, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  clipman_history_show_popup (self->history);
}

static void
on_status_icon_popup (GtkStatusIcon *icon, guint button, guint time,
                      gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  gtk_menu_popup_at_pointer (GTK_MENU (self->menu), NULL);
}

static void
on_menu_show_history (GtkMenuItem *item, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);
  clipman_history_show_popup (self->history);
}

static void
on_menu_preferences (GtkMenuItem *item, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);

  if (!self->preferences)
    self->preferences = clipman_preferences_new (NULL, self->settings);

  gtk_window_present (GTK_WINDOW (self->preferences));
}

static void
on_menu_clear_history (GtkMenuItem *item, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);
  on_clear_requested (self->history, self);
}

static void
on_menu_about (GtkMenuItem *item, gpointer user_data)
{
  const gchar *authors[] = { "Kerem Soke", NULL };

  gtk_show_about_dialog (NULL, "program-name", _ ("MATE Clipboard Manager"),
                         "version", PACKAGE_VERSION, "comments",
                         _ ("A clipboard history manager for MATE Desktop"),
                         "copyright", "Copyright \xc2\xa9 2025",
                         "license-type", GTK_LICENSE_GPL_3_0, "authors",
                         authors, "logo-icon-name", "edit-paste", NULL);
}

static void
on_menu_quit (GtkMenuItem *item, gpointer user_data)
{
  ClipmanApp *self = CLIPMAN_APP (user_data);
  g_application_quit (G_APPLICATION (self));
}

static void
create_status_icon (ClipmanApp *self)
{
  GtkWidget *item;

  /* Create menu */
  self->menu = gtk_menu_new ();

  item = gtk_menu_item_new_with_label (_ ("Show History"));
  g_signal_connect (item, "activate", G_CALLBACK (on_menu_show_history), self);
  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu), item);

  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu),
                         gtk_separator_menu_item_new ());

  item = gtk_menu_item_new_with_label (_ ("Clear History"));
  g_signal_connect (item, "activate", G_CALLBACK (on_menu_clear_history),
                    self);
  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu), item);

  item = gtk_menu_item_new_with_label (_ ("Preferences"));
  g_signal_connect (item, "activate", G_CALLBACK (on_menu_preferences), self);
  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu), item);

  item = gtk_menu_item_new_with_label (_ ("About"));
  g_signal_connect (item, "activate", G_CALLBACK (on_menu_about), self);
  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu), item);

  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu),
                         gtk_separator_menu_item_new ());

  item = gtk_menu_item_new_with_label (_ ("Quit"));
  g_signal_connect (item, "activate", G_CALLBACK (on_menu_quit), self);
  gtk_menu_shell_append (GTK_MENU_SHELL (self->menu), item);

  gtk_widget_show_all (self->menu);

  /* Create status icon */
  self->status_icon = gtk_status_icon_new_from_icon_name ("edit-paste");
  gtk_status_icon_set_tooltip_text (self->status_icon,
                                    _ ("MATE Clipboard Manager"));
  gtk_status_icon_set_visible (self->status_icon, TRUE);

  g_signal_connect (self->status_icon, "activate",
                    G_CALLBACK (on_status_icon_activate), self);
  g_signal_connect (self->status_icon, "popup-menu",
                    G_CALLBACK (on_status_icon_popup), self);
}

static void
clipman_app_startup (GApplication *app)
{
  ClipmanApp *self = CLIPMAN_APP (app);
  static GActionEntry actions[] = {
    { "show-history", show_history_action, NULL, NULL, NULL },
    { "preferences", show_preferences_action, NULL, NULL, NULL },
    { "clear", clear_history_action, NULL, NULL, NULL },
    { "quit", quit_action, NULL, NULL, NULL },
  };

  G_APPLICATION_CLASS (clipman_app_parent_class)->startup (app);

  /* Add actions */
  g_action_map_add_action_entries (G_ACTION_MAP (app), actions,
                                   G_N_ELEMENTS (actions), self);

  /* Initialize settings */
  self->settings = g_settings_new ("org.mate.clipman");

  /* Initialize storage */
  self->storage = clipman_storage_new ();

  /* Initialize clipboard manager */
  self->manager = clipman_manager_new ();
  clipman_manager_set_settings (self->manager, self->settings);

  g_signal_connect (self->manager, "item-received",
                    G_CALLBACK (on_item_received), self);
  g_signal_connect (self->manager, "clipboard-empty",
                    G_CALLBACK (on_clipboard_empty), self);

  /* Initialize history window */
  self->history = clipman_history_new (self->storage, self->settings);

  g_signal_connect (self->history, "item-selected",
                    G_CALLBACK (on_item_selected), self);
  g_signal_connect (self->history, "item-deleted",
                    G_CALLBACK (on_item_deleted), self);
  g_signal_connect (self->history, "clear-requested",
                    G_CALLBACK (on_clear_requested), self);

  /* Create status icon */
  create_status_icon (self);

  /* Start monitoring */
  clipman_manager_start (self->manager);

  /* Hold the application to prevent it from quitting */
  g_application_hold (app);
}

static void
clipman_app_activate (GApplication *app)
{
  ClipmanApp *self = CLIPMAN_APP (app);

  if (!self->start_hidden)
    {
      clipman_history_show_popup (self->history);
    }
  else
    {
      /* Only suppress the very first activation when started hidden */
      self->start_hidden = FALSE;
    }
}

static gint
clipman_app_handle_local_options (GApplication *app, GVariantDict *options)
{
  ClipmanApp *self = CLIPMAN_APP (app);

  if (g_variant_dict_contains (options, "hidden"))
    {
      self->start_hidden = TRUE;
    }

  return -1; /* Continue processing */
}

static void
clipman_app_shutdown (GApplication *app)
{
  ClipmanApp *self = CLIPMAN_APP (app);

  clipman_manager_stop (self->manager);

  /* Disconnect signal handlers before destroying objects */
  if (self->manager)
    {
      g_signal_handlers_disconnect_by_data (self->manager, self);
    }
  if (self->history)
    {
      g_signal_handlers_disconnect_by_data (self->history, self);
    }
  if (self->status_icon)
    {
      g_signal_handlers_disconnect_by_data (self->status_icon, self);
    }

  g_clear_object (&self->manager);
  g_clear_object (&self->storage);
  g_clear_object (&self->settings);
  g_clear_object (&self->status_icon);

  if (self->history)
    gtk_widget_destroy (GTK_WIDGET (self->history));
  if (self->preferences)
    gtk_widget_destroy (GTK_WIDGET (self->preferences));
  if (self->menu)
    gtk_widget_destroy (self->menu);

  G_APPLICATION_CLASS (clipman_app_parent_class)->shutdown (app);
}

static void
clipman_app_class_init (ClipmanAppClass *klass)
{
  GApplicationClass *app_class = G_APPLICATION_CLASS (klass);

  app_class->startup = clipman_app_startup;
  app_class->activate = clipman_app_activate;
  app_class->shutdown = clipman_app_shutdown;
  app_class->handle_local_options = clipman_app_handle_local_options;
}

static void
clipman_app_init (ClipmanApp *self)
{
  g_application_add_main_option (G_APPLICATION (self), "hidden", 'h',
                                 G_OPTION_FLAG_NONE, G_OPTION_ARG_NONE,
                                 _ ("Start hidden in system tray"), NULL);
}

ClipmanApp *
clipman_app_new (void)
{
  return g_object_new (CLIPMAN_TYPE_APP, "application-id", "org.mate.clipman",
                       "flags", G_APPLICATION_FLAGS_NONE, NULL);
}
