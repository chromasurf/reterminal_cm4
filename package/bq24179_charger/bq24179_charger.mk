################################################################################
#
# bq24179_charger
#
################################################################################

BQ24179_CHARGER_VERSION = 0.1
BQ24179_CHARGER_SITE = $(NERVES_DEFCONFIG_DIR)/package/bq24179_charger/src
BQ24179_CHARGER_SITE_METHOD = local

$(eval $(kernel-module))
$(eval $(generic-package))
