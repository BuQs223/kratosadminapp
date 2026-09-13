import GorhomBottomSheet, { BottomSheetView } from '@gorhom/bottom-sheet';
import React from 'react';
import {
  AccessibilityInfo,
  Modal,
  Pressable,
  StyleSheet,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';

interface BottomSheetModalProps extends React.PropsWithChildren {
  visible: boolean;
  onClose: () => void;
  sheetStyle?: StyleProp<ViewStyle>;
  snapPoints?: (string | number)[];
  initialIndex?: number;
  dynamic?: boolean;
  /**
   * Keeps BottomSheetScrollView descendants directly inside Gorhom's sheet so
   * the library can register and control their gestures correctly.
   */
  scrollable?: boolean;
  maxDynamicContentSize?: number;
  keyboardAvoiding?: boolean;
  disableDismiss?: boolean;
  backdropColor?: string;
}

/**
 * Controlled adapter for the gesture-aware sheet. The native Modal is static
 * and sits above Expo NativeTabs; only the sheet itself animates. This keeps
 * the backdrop fixed while opening and closing on every screen.
 */
export function BottomSheetModal({
  visible,
  onClose,
  sheetStyle,
  snapPoints = ['50%', '85%'],
  initialIndex,
  dynamic = false,
  scrollable = false,
  maxDynamicContentSize,
  keyboardAvoiding = false,
  disableDismiss = false,
  backdropColor = '#00000066',
  children,
}: BottomSheetModalProps) {
  const ref = React.useRef<React.ComponentRef<typeof GorhomBottomSheet>>(null);
  const [isClosing, setIsClosing] = React.useState(false);
  // Dynamic sizing creates one content-driven detent, so it must always open
  // at index 0. Fixed sheets retain the caller-selected snap point.
  const selectedIndex = dynamic ? 0 : (initialIndex ?? Math.max(snapPoints.length - 1, 0));

  const requestClose = React.useCallback(() => {
    if (!disableDismiss) {
      // Keep the native modal mounted while the panel finishes its own close
      // animation, so the backdrop never travels with it or flashes away.
      setIsClosing(true);
      ref.current?.close();
    }
  }, [disableDismiss]);

  const handleClose = React.useCallback(() => {
    setIsClosing(false);
    if (visible) {
      // Let navigation settle before a screen moves focus back to its opener.
      void AccessibilityInfo.announceForAccessibility('Fereastră închisă');
      onClose();
    }
  }, [onClose, visible]);

  return (
    <Modal
      visible={visible || isClosing}
      transparent
      animationType="none"
      statusBarTranslucent
      onRequestClose={requestClose}>
      <GestureHandlerRootView style={styles.modalRoot}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Închide fereastra"
          accessibilityState={{ disabled: disableDismiss }}
          disabled={disableDismiss}
          style={[StyleSheet.absoluteFill, { backgroundColor: backdropColor }]}
          onPress={requestClose}
        />
        <GorhomBottomSheet
          ref={ref}
          index={visible && !isClosing ? selectedIndex : -1}
          snapPoints={dynamic ? undefined : snapPoints}
          enableDynamicSizing={dynamic}
          maxDynamicContentSize={maxDynamicContentSize}
          animateOnMount
          enablePanDownToClose={!disableDismiss}
          enableContentPanningGesture={!disableDismiss}
          enableHandlePanningGesture={!disableDismiss}
          keyboardBehavior="interactive"
          keyboardBlurBehavior="restore"
          android_keyboardInputMode="adjustResize"
          bottomInset={0}
          onClose={handleClose}
          backgroundStyle={sheetStyle}
          handleIndicatorStyle={{ width: 40 }}>
          {scrollable ? children : <BottomSheetView style={{ flex: 1 }} accessibilityViewIsModal>{children}</BottomSheetView>}
        </GorhomBottomSheet>
      </GestureHandlerRootView>
    </Modal>
  );
}

const styles = StyleSheet.create({
  modalRoot: { flex: 1 },
});
