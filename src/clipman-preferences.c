/*
 * clipman-preferences.c
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

struct _ClipmanPreferences
{
  GtkDialog parent;

  GSettings *settings;

  GtkWidget *history_size_spin;
  GtkWidget *use_primary_check;
  GtkWidget *sync_selections_check;
  GtkWidget *save_images_check;
  GtkWidget *save_files_check;
  GtkWidget *keep_content_check;
  GtkWidget *show_preview_check;
  GtkWidget *confirm_clear_check;
  GtkWidget *paste_on_select_check;
  GtkWidget *exclude_pattern_entry;
};

G_DEFINE_TYPE (ClipmanPreferences, clipman_preferences, GTK_TYPE_DIALOG)

static void
clipman_preferences_dispose (GObject *object)
{
  ClipmanPreferences *self = CLIPMAN_PREFERENCES (object);

  g_clear_object (&self->settings);

  G_OBJECT_CLASS (clipman_preferences_parent_class)->dispose (object);
}

static void
clipman_preferences_class_init (ClipmanPreferencesClass *klass)
{
  GObjectClass *object_class = G_OBJECT_CLASS (klass);

  object_class->dispose = clipman_preferences_dispose;
}

static GtkWidget *
create_section_label (const gchar *text)
{
  GtkWidget *label;
  gchar *markup;

  label = gtk_label_new (NULL);
  markup = g_strdup_printf ("<b>%s</b>", text);
  gtk_label_set_markup (GTK_LABEL (label), markup);
  g_free (markup);

  gtk_label_set_xalign (GTK_LABEL (label), 0.0);
  gtk_widget_set_margin_top (label, 12);
  gtk_widget_set_margin_bottom (label, 6);

  return label;
}

static GtkWidget *
create_indented_widget (GtkWidget *widget)
{
  GtkWidget *box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_margin_start (box, 12);
  gtk_box_pack_start (GTK_BOX (box), widget, TRUE, TRUE, 0);
  return box;
}

static void
clipman_preferences_init (ClipmanPreferences *self)
{
  GtkWidget *content;
  GtkWidget *vbox;
  GtkWidget *grid;
  GtkWidget *label;
  GtkWidget *box;

  gtk_window_set_title (GTK_WINDOW (self), "Clipboard Manager Preferences");
  gtk_window_set_default_size (GTK_WINDOW (self), 450, -1);
  gtk_window_set_resizable (GTK_WINDOW (self), FALSE);

  gtk_dialog_add_button (GTK_DIALOG (self), "_Close", GTK_RESPONSE_CLOSE);

  content = gtk_dialog_get_content_area (GTK_DIALOG (self));
  gtk_container_set_border_width (GTK_CONTAINER (content), 12);

  vbox = gtk_box_new (GTK_ORIENTATION_VERTICAL, 6);
  gtk_container_add (GTK_CONTAINER (content), vbox);

  /* General section */
  gtk_box_pack_start (GTK_BOX (vbox), create_section_label ("General"), FALSE,
                      FALSE, 0);

  grid = gtk_grid_new ();
  gtk_grid_set_column_spacing (GTK_GRID (grid), 12);
  gtk_grid_set_row_spacing (GTK_GRID (grid), 6);
  gtk_box_pack_start (GTK_BOX (vbox), create_indented_widget (grid), FALSE,
                      FALSE, 0);

  label = gtk_label_new ("History size:");
  gtk_label_set_xalign (GTK_LABEL (label), 0.0);
  gtk_grid_attach (GTK_GRID (grid), label, 0, 0, 1, 1);

  self->history_size_spin = gtk_spin_button_new_with_range (1, 500, 1);
  gtk_widget_set_tooltip_text (self->history_size_spin,
                               "Maximum number of items to keep in history");
  gtk_grid_attach (GTK_GRID (grid), self->history_size_spin, 1, 0, 1, 1);

  self->keep_content_check = gtk_check_button_new_with_label (
      "Keep clipboard content when source closes");
  gtk_widget_set_tooltip_text (
      self->keep_content_check,
      "Restore clipboard content when the application that copied it closes");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->keep_content_check), FALSE,
                      FALSE, 0);

  self->confirm_clear_check
      = gtk_check_button_new_with_label ("Confirm before clearing history");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->confirm_clear_check),
                      FALSE, FALSE, 0);

  self->paste_on_select_check = gtk_check_button_new_with_label (
      "Automatically paste when selecting from history");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->paste_on_select_check),
                      FALSE, FALSE, 0);

  /* Clipboard section */
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_section_label ("Clipboard Sources"), FALSE, FALSE,
                      0);

  self->use_primary_check = gtk_check_button_new_with_label (
      "Track primary selection (middle-click paste)");
  gtk_widget_set_tooltip_text (self->use_primary_check,
                               "Also save text selected with the mouse");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->use_primary_check), FALSE,
                      FALSE, 0);

  self->sync_selections_check = gtk_check_button_new_with_label (
      "Synchronize clipboard and primary selection");
  gtk_widget_set_tooltip_text (self->sync_selections_check,
                               "Keep both selections synchronized");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->sync_selections_check),
                      FALSE, FALSE, 0);

  /* Content types section */
  gtk_box_pack_start (GTK_BOX (vbox), create_section_label ("Content Types"),
                      FALSE, FALSE, 0);

  self->save_images_check
      = gtk_check_button_new_with_label ("Save images to history");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->save_images_check), FALSE,
                      FALSE, 0);

  self->save_files_check
      = gtk_check_button_new_with_label ("Save file paths to history");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->save_files_check), FALSE,
                      FALSE, 0);

  self->show_preview_check
      = gtk_check_button_new_with_label ("Show image previews in history");
  gtk_box_pack_start (GTK_BOX (vbox),
                      create_indented_widget (self->show_preview_check), FALSE,
                      FALSE, 0);

  /* Filter section */
  gtk_box_pack_start (GTK_BOX (vbox), create_section_label ("Filtering"),
                      FALSE, FALSE, 0);

  box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
  label = gtk_label_new ("Exclude pattern:");
  gtk_box_pack_start (GTK_BOX (box), label, FALSE, FALSE, 0);

  self->exclude_pattern_entry = gtk_entry_new ();
  gtk_entry_set_placeholder_text (GTK_ENTRY (self->exclude_pattern_entry),
                                  "Regular expression");
  gtk_widget_set_tooltip_text (
      self->exclude_pattern_entry,
      "Text matching this pattern will not be saved (e.g., passwords)");
  gtk_widget_set_hexpand (self->exclude_pattern_entry, TRUE);
  gtk_box_pack_start (GTK_BOX (box), self->exclude_pattern_entry, TRUE, TRUE,
                      0);

  gtk_box_pack_start (GTK_BOX (vbox), create_indented_widget (box), FALSE,
                      FALSE, 0);

  gtk_widget_show_all (vbox);

  g_signal_connect (self, "response", G_CALLBACK (gtk_widget_hide), NULL);
}

ClipmanPreferences *
clipman_preferences_new (GtkWindow *parent, GSettings *settings)
{
  ClipmanPreferences *self;

  self = g_object_new (CLIPMAN_TYPE_PREFERENCES, "transient-for", parent,
                       "modal", TRUE, NULL);

  if (settings)
    {
      self->settings = g_object_ref (settings);

      /* Bind settings to widgets */
      g_settings_bind (settings, "history-size",
                       gtk_spin_button_get_adjustment (
                           GTK_SPIN_BUTTON (self->history_size_spin)),
                       "value", G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "use-primary-selection",
                       self->use_primary_check, "active",
                       G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "sync-selections",
                       self->sync_selections_check, "active",
                       G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "save-images", self->save_images_check,
                       "active", G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "save-files", self->save_files_check,
                       "active", G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "keep-content", self->keep_content_check,
                       "active", G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "show-preview", self->show_preview_check,
                       "active", G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "confirm-clear", self->confirm_clear_check,
                       "active", G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "paste-on-select",
                       self->paste_on_select_check, "active",
                       G_SETTINGS_BIND_DEFAULT);

      g_settings_bind (settings, "exclude-pattern",
                       self->exclude_pattern_entry, "text",
                       G_SETTINGS_BIND_DEFAULT);
    }

  return self;
}
