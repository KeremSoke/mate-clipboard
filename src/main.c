/*
 * main.c
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

int
main (int argc, char *argv[])
{
  ClipmanApp *app;
  int status;

  /* Ensure X11 backend for clipboard operations */
  gdk_set_allowed_backends ("x11");

  app = clipman_app_new ();
  status = g_application_run (G_APPLICATION (app), argc, argv);
  g_object_unref (app);

  return status;
}
