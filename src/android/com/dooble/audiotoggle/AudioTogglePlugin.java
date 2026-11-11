package com.dooble.audiotoggle;

import android.bluetooth.BluetoothHeadset;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothProfile;
import android.bluetooth.BluetoothDevice;
import android.content.Context;
import android.media.AudioManager;
import android.media.AudioDeviceInfo;
import java.util.List;
import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.BroadcastReceiver;
import org.apache.cordova.CordovaWebView;
import org.apache.cordova.CordovaInterface;
import org.apache.cordova.PluginResult;
import org.apache.cordova.PluginResult.Status;
import android.util.Log;
import android.os.Build;
import java.lang.reflect.InvocationTargetException;
import android.content.pm.PackageManager;
import android.media.AudioDeviceCallback;
import android.os.Handler;
import android.os.Looper;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;
import java.util.concurrent.Executor;

public class AudioTogglePlugin extends CordovaPlugin {
  public static final String ACTION_SET_AUDIO_MODE = "setAudioMode";
  public static final String ACTION_SET_BLUETOOTH_ON = "setBluetoothScoOn";
  public static final String ACTION_SET_SPEAKER_ON = "setSpeakerphoneOn";
  public static final String ACTION_GET_OUTPUT_DEVICES = "getOutputDevices";
  public static final String ACTION_GET_AUDIO_MODE = "getAudioMode";
  public static final String ACTION_IS_SPEAKER_ON = "isSpeakerphoneOn";
  public static final String ACTION_IS_BLUETOOTH_ON = "isBluetoothScoOn";
  public static final String ACTION_HAS_EARPIECE = "hasBuiltInEarpiece";
  public static final String ACTION_HAS_SPEAKER = "hasBuiltInSpeaker";
  public static final String ACIONT_REGISTER_LISTENER = "registerListener";

  private static final String LOG_TAG = "AudioTogglePlugin";
  private static final String BLUETOOTH_CONNECT = "android.permission.BLUETOOTH_CONNECT";
  private static final int BLUETOOTH_PERMISSION_REQUEST = 4101;
  private static final String MODE_LISTENER_CLASS = "android.media.AudioManager$OnModeChangedListener";
  private static final int TYPE_USB_HEADSET = 22;
  private static final int TYPE_HEARING_AID = 23;
  private static final int TYPE_BLE_HEADSET = 26;
  private static final int TYPE_BLE_SPEAKER = 27;
  private static final int TYPE_BLE_BROADCAST = 30;
  BroadcastReceiver receiver;
  CallbackContext speakerListener;
  BroadcastReceiver scoReceiver;
  AudioDeviceCallback deviceCallback;
  Object modeListener;
  boolean bluetoothPermissionRequested;
  String lastLoggedRoute;

  public AudioTogglePlugin(){
    receiver = null;
    speakerListener = null;
  } 

  @Override
  public void initialize(CordovaInterface cordova, CordovaWebView webView) {
      super.initialize(cordova, webView);
      IntentFilter intentFilter = new IntentFilter();
      intentFilter.addAction(Intent.ACTION_HEADSET_PLUG);
      intentFilter.addAction(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED);
     // this requires api 29
     // intentFilter.addAction(AudioManager.ACTION_SPEAKERPHONE_STATE_CHANGED);
      this.receiver = new BroadcastReceiver() {
          @Override
          public void onReceive(Context context, Intent intent) {
                Boolean isSpeakerOn = isSpeakerphoneOn();
                if(speakerListener != null ){
                    PluginResult result = new PluginResult(Status.OK, isSpeakerOn.toString());
                    result.setKeepCallback(true);
                    speakerListener.sendPluginResult(result);
                }
          }
      };
      webView.getContext().registerReceiver(this.receiver, intentFilter);
      registerRouteLogging();
      logRoute("plugin start");
  }

  @Override
  public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
    if (action.equals(ACTION_SET_AUDIO_MODE)) {
      if (!setAudioMode(args.getString(0))) {
        callbackContext.error("Invalid audio mode");
        return false;
      }

      logRoute("setAudioMode " + args.getString(0));
      return true;
    } else if (action.equals(ACTION_SET_BLUETOOTH_ON)) {
      setBluetoothScoOn(args.getBoolean(0));
      logRoute("setBluetoothScoOn " + args.getBoolean(0));
      return true;
    } else if (action.equals(ACTION_SET_SPEAKER_ON)) {
      setSpeakerphoneOn(args.getBoolean(0));
      logRoute("setSpeakerphoneOn " + args.getBoolean(0));
      return true;
    } else if (action.equals(ACTION_GET_OUTPUT_DEVICES)) {
      callbackContext.success(getOutputDevices());
      return true;
    } else if (action.equals(ACTION_GET_AUDIO_MODE)) {
      callbackContext.success(getAudioMode());
      return true;
    } else if (action.equals(ACTION_IS_SPEAKER_ON)) {
      logRouteIfChanged("speaker state read");
      callbackContext.success(isSpeakerphoneOn().toString());
      return true;
    } else if (action.equals(ACTION_IS_BLUETOOTH_ON)) {
      callbackContext.success(isBluetoothScoOn().toString());
      return true;
    } else if (action.equals(ACTION_HAS_EARPIECE)) {
      callbackContext.success(hasBuiltInEarpiece().toString());
      return true;
    } else if (action.equals(ACTION_HAS_SPEAKER)) {
      callbackContext.success(hasBuiltInSpeaker().toString());
      return true;
    } else if(action.equals(ACIONT_REGISTER_LISTENER)){
      String eventName = args.getString(0);
      if("speaker".equalsIgnoreCase(eventName)){
        this.speakerListener = callbackContext;
      }
      return true;
    }

    callbackContext.error("Invalid action");
    return false;
  }

  public Boolean hasBuiltInEarpiece() {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    try {
      AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);

      JSONArray retdevs = new JSONArray();
      for (AudioDeviceInfo dev : devices) {
        if (dev.isSink()) {
          if (dev.getType() == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE) {
            return true;
          }
        }
      }

      return false;
    } catch (Exception e) {
      return false;
    }
  }

  public Boolean hasBuiltInSpeaker() {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    try {
      AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);

      JSONArray retdevs = new JSONArray();
      for (AudioDeviceInfo dev : devices) {
        if (dev.isSink()) {
          if (dev.getType() == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
            return true;
          }
        }
      }

      return false;
    } catch (Exception e) {
      return false;
    }
  }

  public void setBluetoothScoOn(boolean on) {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    audioManager.setBluetoothScoOn(on);
    if (on) {
      audioManager.startBluetoothSco();
    } else {
      audioManager.stopBluetoothSco();
    }
  }

  public void setSpeakerphoneOn(boolean on) {
      final Context context = webView.getContext();
      final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

      if(isAfter31()){
          int deviceType = on ? AudioDeviceInfo.TYPE_BUILTIN_SPEAKER : AudioDeviceInfo.TYPE_BUILTIN_EARPIECE;
          setCommunicationDevice(audioManager, deviceType);
      }else {
          audioManager.setSpeakerphoneOn(on);
      }
  }

  private boolean isAfter31() {
      return Build.VERSION.SDK_INT >= 31;
  }

  private void setCommunicationDevice(AudioManager mgr, int deviceType) {
      try {
          List<AudioDeviceInfo> devices = (List<AudioDeviceInfo>) mgr.getClass().getMethod("getAvailableCommunicationDevices").invoke(mgr);
          for (AudioDeviceInfo device : devices) {
              if (device.getType() == deviceType) {
                  mgr.getClass().getMethod("setCommunicationDevice").invoke(mgr, device);
                  return;
              }
          }
      } catch (IllegalAccessException e){
          e.printStackTrace();
      } catch(InvocationTargetException e){
          e.printStackTrace();
      } catch(NoSuchMethodException e) {
          e.printStackTrace();
      }
  }

  public boolean setAudioMode(String mode) {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    if (mode.equals("bluetooth")) {
      audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
      audioManager.setBluetoothScoOn(true);
      audioManager.startBluetoothSco();
      audioManager.setSpeakerphoneOn(false);
      return true;
    } else if (mode.equals("earpiece")) {
      audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
      audioManager.stopBluetoothSco();
      audioManager.setBluetoothScoOn(false);
      audioManager.setSpeakerphoneOn(false);
      return true;
    } else if (mode.equals("speaker")) {
      audioManager.setMode(AudioManager.MODE_NORMAL);
      audioManager.stopBluetoothSco();
      audioManager.setBluetoothScoOn(false);
      audioManager.setSpeakerphoneOn(true);
      return true;
    } else if (mode.equals("ringtone")) {
      audioManager.setMode(AudioManager.MODE_RINGTONE);
      audioManager.setSpeakerphoneOn(false);
      return true;
    } else if (mode.equals("normal")) {
      audioManager.setMode(AudioManager.MODE_NORMAL);
      audioManager.setSpeakerphoneOn(false);
      return true;
    }

    return false;
  }

  public JSONObject getOutputDevices() {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    try {
      AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS);

      JSONArray retdevs = new JSONArray();
      for (AudioDeviceInfo dev : devices) {
        if (dev.isSink()) {
          if (dev.getType() != AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
              && dev.getType() != AudioDeviceInfo.TYPE_BUILTIN_SPEAKER) {
            retdevs.put(new JSONObject().put("id", dev.getId()).put("type", dev.getType()).put("name",
                dev.getProductName().toString()));
          }
        }
      }

      return new JSONObject().put("devices", retdevs);
    } catch (JSONException e) {
      // lets hope json-object keys are not null and not duplicated :)
    }

    return new JSONObject();
  }

  public String getAudioMode() {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    int mode = audioManager.getMode();
    boolean isBluetoothScoOn = audioManager.isBluetoothScoOn();
    boolean isSpeakerphoneOn = audioManager.isSpeakerphoneOn();

    if (mode == AudioManager.MODE_IN_COMMUNICATION && isBluetoothScoOn) {
      return "bluetooth";
    } else if (mode == AudioManager.MODE_IN_COMMUNICATION && !isBluetoothScoOn && !isSpeakerphoneOn) {
      return "earpiece";
    } else if (mode == AudioManager.MODE_IN_COMMUNICATION && !isBluetoothScoOn && isSpeakerphoneOn) {
      return "speaker";
    } else if (mode == AudioManager.MODE_RINGTONE && !isSpeakerphoneOn) {
      return "ringtone";
    } else if (mode == AudioManager.MODE_NORMAL && !isSpeakerphoneOn) {
      return "normal";
    }

    return "normal";
  }

  public Boolean isBluetoothScoOn() {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    return audioManager.isBluetoothScoOn();
  }

  public Boolean isSpeakerphoneOn() {
    final Context context = webView.getContext();
    final AudioManager audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);

    return audioManager.isSpeakerphoneOn();
  }

  @Override
  public void onDestroy() {
    if (scoReceiver != null) {
      webView.getContext().unregisterReceiver(scoReceiver);
    }
    if (deviceCallback != null) {
      getAudioManager().unregisterAudioDeviceCallback(deviceCallback);
    }
    if (modeListener != null) {
      try {
        AudioManager audioManager = getAudioManager();
        audioManager.getClass().getMethod("removeOnModeChangedListener", Class.forName(MODE_LISTENER_CLASS))
            .invoke(audioManager, modeListener);
      } catch (Exception e) {
        Log.w(LOG_TAG, "removeOnModeChangedListener failed", e);
      }
    }
    super.onDestroy();
  }

  @Override
  public void onRequestPermissionResult(int requestCode, String[] permissions, int[] grantResults) throws JSONException {
    if (requestCode != BLUETOOTH_PERMISSION_REQUEST) {
      return;
    }
    boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
    logRoute("BLUETOOTH_CONNECT " + (granted ? "granted" : "denied"));
  }

  private void registerRouteLogging() {
    AudioManager audioManager = getAudioManager();

    scoReceiver = new BroadcastReceiver() {
      @Override
      public void onReceive(Context context, Intent intent) {
        int state = intent.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, AudioManager.SCO_AUDIO_STATE_ERROR);
        logRoute("bluetooth sco " + scoStateName(state));
      }
    };
    webView.getContext().registerReceiver(scoReceiver, new IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED));

    if (Build.VERSION.SDK_INT >= 23) {
      deviceCallback = new AudioDeviceCallback() {
        @Override
        public void onAudioDevicesAdded(AudioDeviceInfo[] addedDevices) {
          logRoute("devices added " + describeDevices(addedDevices));
          maybeRequestBluetoothPermission("audio device added");
        }

        @Override
        public void onAudioDevicesRemoved(AudioDeviceInfo[] removedDevices) {
          logRoute("devices removed " + describeDevices(removedDevices));
        }
      };
      audioManager.registerAudioDeviceCallback(deviceCallback, null);
    }

    if (isAfter31()) {
      addModeChangedListener(audioManager);
    }
  }

  /* OnModeChangedListener is API 31 and the build compiles against an older
   * SDK, so the listener is a Proxy registered by reflection. */
  private void addModeChangedListener(AudioManager audioManager) {
    try {
      Class<?> listenerClass = Class.forName(MODE_LISTENER_CLASS);
      modeListener = Proxy.newProxyInstance(getClass().getClassLoader(), new Class<?>[] { listenerClass },
          new InvocationHandler() {
            @Override
            public Object invoke(Object proxy, Method method, Object[] args) {
              if ("onModeChanged".equals(method.getName())) {
                logRoute("mode changed");
                maybeRequestBluetoothPermission("call audio started");
                return null;
              }
              if ("equals".equals(method.getName())) {
                return proxy == args[0];
              }
              if ("hashCode".equals(method.getName())) {
                return System.identityHashCode(proxy);
              }
              return "AudioToggleModeListener";
            }
          });
      audioManager.getClass().getMethod("addOnModeChangedListener", Executor.class, listenerClass)
          .invoke(audioManager, mainThreadExecutor(), modeListener);
    } catch (Exception e) {
      modeListener = null;
      Log.w(LOG_TAG, "addOnModeChangedListener failed", e);
    }
  }

  private Executor mainThreadExecutor() {
    final Handler handler = new Handler(Looper.getMainLooper());
    return new Executor() {
      @Override
      public void execute(Runnable command) {
        handler.post(command);
      }
    };
  }

  /* The WebView's WebRTC (camera on) only uses a Bluetooth headset on
   * Android 12+ with BLUETOOTH_CONNECT. Ask during a call and only when a
   * Bluetooth device is connected, so most students never see the prompt. */
  private void maybeRequestBluetoothPermission(String why) {
    if (!isAfter31() || bluetoothPermissionRequested || cordova.hasPermission(BLUETOOTH_CONNECT)) {
      return;
    }
    AudioManager audioManager = getAudioManager();
    if (audioManager.getMode() != AudioManager.MODE_IN_COMMUNICATION || !hasBluetoothOutput(audioManager)
        || !cordova.getActivity().hasWindowFocus()) {
      return;
    }
    bluetoothPermissionRequested = true;
    Log.i(LOG_TAG, "requesting BLUETOOTH_CONNECT: " + why);
    cordova.requestPermission(this, BLUETOOTH_PERMISSION_REQUEST, BLUETOOTH_CONNECT);
  }

  private boolean hasBluetoothOutput(AudioManager audioManager) {
    for (AudioDeviceInfo device : audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)) {
      if (isBluetoothType(device.getType())) {
        return true;
      }
    }
    return false;
  }

  private boolean isBluetoothType(int type) {
    return type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP
        || type == TYPE_BLE_HEADSET || type == TYPE_BLE_SPEAKER || type == TYPE_BLE_BROADCAST;
  }

  private AudioManager getAudioManager() {
    return (AudioManager) webView.getContext().getSystemService(Context.AUDIO_SERVICE);
  }

  private void logRoute(String why) {
    String route = describeRoute();
    lastLoggedRoute = route;
    Log.i(LOG_TAG, why + ": " + route);
  }

  private void logRouteIfChanged(String why) {
    if (!describeRoute().equals(lastLoggedRoute)) {
      logRoute(why);
    }
  }

  private String describeRoute() {
    AudioManager audioManager = getAudioManager();
    StringBuilder route = new StringBuilder();
    route.append("mode=").append(modeName(audioManager.getMode()))
        .append(" speaker=").append(audioManager.isSpeakerphoneOn())
        .append(" sco=").append(audioManager.isBluetoothScoOn());
    if (isAfter31()) {
      route.append(" device=").append(describeDevice(getCommunicationDevice(audioManager)))
          .append(" bluetoothPermission=").append(cordova.hasPermission(BLUETOOTH_CONNECT));
    }
    if (Build.VERSION.SDK_INT >= 23) {
      route.append(" outputs=").append(describeDevices(audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)));
    }
    return route.toString();
  }

  private AudioDeviceInfo getCommunicationDevice(AudioManager audioManager) {
    try {
      return (AudioDeviceInfo) audioManager.getClass().getMethod("getCommunicationDevice").invoke(audioManager);
    } catch (Exception e) {
      return null;
    }
  }

  private String describeDevices(AudioDeviceInfo[] devices) {
    StringBuilder names = new StringBuilder("[");
    for (int i = 0; i < devices.length; i++) {
      if (i > 0) {
        names.append(", ");
      }
      names.append(describeDevice(devices[i]));
    }
    return names.append("]").toString();
  }

  private String describeDevice(AudioDeviceInfo device) {
    if (device == null) {
      return "none";
    }
    return deviceTypeName(device.getType()) + (device.isSink() ? "" : "-in") + ":" + device.getProductName();
  }

  private String deviceTypeName(int type) {
    switch (type) {
      case AudioDeviceInfo.TYPE_BUILTIN_EARPIECE: return "earpiece";
      case AudioDeviceInfo.TYPE_BUILTIN_SPEAKER: return "speaker";
      case AudioDeviceInfo.TYPE_BUILTIN_MIC: return "builtinMic";
      case AudioDeviceInfo.TYPE_WIRED_HEADSET: return "wiredHeadset";
      case AudioDeviceInfo.TYPE_WIRED_HEADPHONES: return "wiredHeadphones";
      case AudioDeviceInfo.TYPE_BLUETOOTH_SCO: return "bluetoothSco";
      case AudioDeviceInfo.TYPE_BLUETOOTH_A2DP: return "bluetoothA2dp";
      case AudioDeviceInfo.TYPE_USB_DEVICE: return "usbDevice";
      case TYPE_USB_HEADSET: return "usbHeadset";
      case AudioDeviceInfo.TYPE_TELEPHONY: return "telephony";
      case TYPE_HEARING_AID: return "hearingAid";
      case TYPE_BLE_HEADSET: return "bleHeadset";
      case TYPE_BLE_SPEAKER: return "bleSpeaker";
      case TYPE_BLE_BROADCAST: return "bleBroadcast";
      default: return "type" + type;
    }
  }

  private String modeName(int mode) {
    switch (mode) {
      case AudioManager.MODE_NORMAL: return "normal";
      case AudioManager.MODE_RINGTONE: return "ringtone";
      case AudioManager.MODE_IN_CALL: return "inCall";
      case AudioManager.MODE_IN_COMMUNICATION: return "inCommunication";
      default: return String.valueOf(mode);
    }
  }

  private String scoStateName(int state) {
    switch (state) {
      case AudioManager.SCO_AUDIO_STATE_CONNECTED: return "connected";
      case AudioManager.SCO_AUDIO_STATE_CONNECTING: return "connecting";
      case AudioManager.SCO_AUDIO_STATE_DISCONNECTED: return "disconnected";
      default: return "error";
    }
  }
}
