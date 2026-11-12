ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES)
endif
include $(GNUSTEP_MAKEFILES)/common.make
APP_NAME = Workspace
Workspace_OBJC_FILES = main.m FVApplication.m FVWindow.m FVModel.m FVOperations.m FVIconView.m FVLauncher.m FVThumbnails.m FVPanels.m FVInspector.m
Workspace_HEADER_FILES = FVApplication.h FVWindow.h FVModel.h FVOperations.h FVIconView.h FVLauncher.h FVThumbnails.h FVPanels.h FVInspector.h
Workspace_RESOURCE_FILES = Resources/Workspace.png Resources/HardDisk.tiff
Workspace_APPLICATION_ICON = Workspace.png
Workspace_OBJCFLAGS = -Wall -Wextra -Wno-unused-parameter
ADDITIONAL_GUI_LIBS += -lX11 -lXext
ifneq (,$(findstring linux,$(GNUSTEP_TARGET_OS)))
ADDITIONAL_GUI_LIBS += -lmount
endif
include $(GNUSTEP_MAKEFILES)/application.make
