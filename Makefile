TOPDIR := $(shell pwd)

.DEFAULT_GOAL := help

DL_DIR := $(TOPDIR)/dl
PARALLEL_JOBS := 8

# config

build-config:
	cp build-config.example build-config

-include build-config

MAKE_BR = make -C buildroot BR2_EXTERNAL=$(TOPDIR) BR2_DL_DIR=$(DL_DIR) -j $(PARALLEL_JOBS)

# global
.buildStep-buildrootDownloaded:
	@echo "Downloading Buildroot..."
	git submodule update --init || exit 1
	@touch .buildStep-buildrootDownloaded

# Apply our patches that either haven't been submitted or merged upstream yet
.buildStep-buildrootPatched: .buildStep-buildrootDownloaded
	buildroot/support/scripts/apply-patches.sh buildroot patches/buildroot || exit 1
	touch .buildStep-buildrootPatched

reset-buildroot: .buildStep-buildrootDownloaded
	# Reset buildroot to a pristine condition so that the
	# patches can be applied again.
	cd buildroot && git clean -fdx && git reset --hard
	rm .buildStep-buildrootPatched

update-patches: reset-buildroot .buildStep-buildrootPatched

help:
	@echo '=== Project Build Help ==='
	@echo
	@echo 'Global actions:'
	@echo "  reset-buildroot        Reset buildroot."
	@echo 
	@echo "Target-specific actions:"
	@echo "  <target>_defconfig     Initialize a target."
	@echo "  <target>_help          Get help for a target."
	@echo
	@echo "Available targets:"
	@$(foreach b, $(sort $(notdir $(wildcard configs/*_defconfig))), \
	  printf "  * %s\\n" $(b:_defconfig=);)
# end - global

# board specific
%_help: %_isInited
	@echo
	@echo
	@echo '=== Target "$(TARGET)" Build Help ==='
	@echo
	@echo "You may use the following commands:"
	@echo "  make $(TARGET)_source          Download all sources so an offline build is possible"
	@echo "  make $(TARGET)_all             Build everything"
	@echo "  make $(TARGET)_clean           Clean everything"
	@echo "  make $(TARGET)_menuconfig      Open the menuconfig"
	@echo "  make $(TARGET)_save            Save to current configuration to the respective defconfig"

%_defconfig: %_isValidTarget
	$(call calculate-target-vars,$@)
	$(MAKE_TARGET) $(TARGET)_defconfig

	@echo
	@echo
	@echo "=== The target $(TARGET) is now initialized! ==="
	@echo 'Please run "make $(TARGET)_help" for a list of available commands.'

%_all: %_isInited
	$(MAKE_TARGET) -j16
	@echo
	@echo "Project has been built successfully."
	@echo "Images are in buildroot/output/images."

%_source: %_isInited
	$(MAKE_TARGET) source
	@echo
	@echo "All sources downloaded"

%_menuconfig: %_isInited
	$(MAKE_TARGET) menuconfig
	@echo
	@echo "----------------------------------------"
	@echo "!!! Important !!!"
	@echo $(TARGET_DEFCONFIG) has NOT been updated.
	@echo "Changes will not be reflected in your git repository."
	@echo "Please run"
	@echo
	@echo "make $(TARGET)_save"
	@echo
	@echo "to update the defconfig."
	@echo "----------------------------------------"
	@echo

%_linux-menuconfig: %_isInited
	$(MAKE_TARGET) linux-menuconfig
	$(MAKE_TARGET) linux-savedefconfig
	@echo
	@echo "----------------------------------------"
	@echo Going to update your boards/$(TARGET)/linux.config. If you do not have one,
	@echo you will get an error shortly. You will then have to make one and update
	@echo your buildroot configuration to use it.
	@echo To do so, place your linux config into boards/$(TARGET)/linux.config
	@echo and add the line 
	@echo BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=\"$$\(BR2_EXTERNAL\)/board/$(TARGET)/linux.config\"
	@echo to your defconfig. Dont forget to run make $(TARGET)_defconfig afterwards.
	@echo "----------------------------------------"
	@echo
	$(MAKE_TARGET) linux-update-defconfig

%_busybox-menuconfig: %_isInited
	$(MAKE_TARGET) busybox-menuconfig
	@echo
	@echo "----------------------------------------"
	@echo Going to update your boards/$(TARGET)/busybox.config. If you do not have one,
	@echo you will get an error shortly. You will then have to make one and update
	@echo your buildroot configuration to use it.
	@echo To do so, place your busybox config into boards/$(TARGET)/busybox.config and add the line 
	@echo BR2_PACKAGE_BUSYBOX_CONFIG=\"$$\(BR2_EXTERNAL\)/board/$(TARGET)/busybox.config\"
	@echo to your defconfig. Dont forget to run make $(TARGET)_defconfig afterwards.
	@echo "----------------------------------------"
	@echo
	$(MAKE_TARGET) busybox-update-config

%_clean: %_isInited
	$(MAKE_TARGET) clean

%_save: %_savedefconfig
	@echo "Done."

%_savedefconfig: %_isInited
	$(MAKE_TARGET) savedefconfig
# end - board specific

# Helper stuff
define calculate-target-vars
	$(eval TARGET := $(word 1,$(subst _, ,$(1))))
	$(eval TARGET_DEFCONFIG := $(TOPDIR)/configs/$(TARGET)_defconfig)
	$(eval TARGET_OUTPUTS := $(TOPDIR)/outputs/$(TARGET))
	$(eval TARGET_IMAGES := $(TARGET_OUTPUTS)/images)
	$(eval MAKE_TARGET := $(MAKE_BR) O=$(TARGET_OUTPUTS))
endef

%_isInited: outputs/%/.config
	@echo "Target is inited!"
	$(call calculate-target-vars,$@)
	@echo "----------------------------------------"
	@echo "TARGET:			$(TARGET)"
	@echo "TARGET_DEFCONFIG: 	$(TARGET_DEFCONFIG)"
	@echo "TARGET_OUTPUTS:		$(TARGET_OUTPUTS)"
	@echo "TARGET_IMAGES:		$(TARGET_IMAGES)"
	@echo "MAKE_TARGET:		$(MAKE_TARGET)"
	@echo "----------------------------------------"

%_isValidTarget: .buildStep-buildrootDownloaded
	$(call calculate-target-vars,$@)
	
	@if [ "$(wildcard $(TARGET_DEFCONFIG))" != "" ]; then	\
		echo "Target is valid!";							\
	else													\
		echo "ERROR: The target is not valid!";\
		echo "Available targets:";\
		for i in `ls configs/*_defconfig | xargs -n 1 basename`;     \
    	do                   \
        	echo "* $$i" | cut -d_ -f1; \
    	done;                \
		echo;\
		false;\
	fi

outputs/%/.config: %_isValidTarget
	$(eval TARGET := $(subst outputs/,,$@))
	$(eval TARGET := $(subst /.config,,$(TARGET)))
	@echo "The target \"$(TARGET)\" is not initialized yet!"
	@echo "Please run"
	@echo
	@echo "make $(TARGET)_defconfig"
	@echo
	@echo "to initialize it!"
	@false
# end - Helper stuff

# Fwup stuff
define fwup-burn
	@echo "fwup: Executing burn task $(1)"
	sudo $(TARGET_OUTPUTS)/host/usr/bin/fwup -a -i $(firstword $(wildcard $(TARGET_IMAGES)/*.fw)) -t $(1) --enable-trim
endef

define fwup-burn-test
	@echo "fwup: Executing burn-test task $(1)"
	$(TARGET_OUTPUTS)/host/usr/bin/fwup -a -d $(firstword $(wildcard $(TARGET_IMAGES)/*.fw)).img -i $(firstword $(wildcard $(TARGET_IMAGES)/*.fw)) -t $(1)
endef

%_burn: %_isInited
	$(call fwup-burn,complete)

%_burn-upgrade: %_isInited
	$(call fwup-burn,upgrade)

%_burn-test: %_isInited
	$(call fwup-burn-test,complete)

%_burn-test-upgrade: %_isInited
	$(call fwup-burn-test,upgrade)
# end - Fwup stuff
