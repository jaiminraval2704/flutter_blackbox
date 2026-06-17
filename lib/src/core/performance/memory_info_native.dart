import 'dart:io' show ProcessInfo;

/// Native implementation using dart:io ProcessInfo.
int getCurrentRss() => ProcessInfo.currentRss;
int getMaxRss() => ProcessInfo.maxRss;
