# The Flutter Gradle plugin adds this file to the release R8 configuration.

# Android names a sensor connection after its listener class, and some vendor
# sensor services match that name against the app (MIUI logs
# "SensorService: check list, getPackageName <name>"). Renamed by R8 to z4.h,
# the Qibla compass looked like nobody's; keep the name it has in debug builds.
-keepnames class forum.iqro.app.QiblaCompassStreamHandler
