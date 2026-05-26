/**
 * CSS-enabled wrappers for core React Native primitives.
 *
 * Use these instead of bare RN components to get Tailwind className support.
 * All components delegate styling to `useCssElement` from react-native-css,
 * which maps the `className` prop → the appropriate style prop at runtime.
 */
import {
  useCssElement,
  useNativeVariable as useFunctionalVariable,
} from 'react-native-css';

import { Link as RouterLink } from 'expo-router';
import Animated from 'react-native-reanimated';
import React from 'react';
import {
  View as RNView,
  Text as RNText,
  Pressable as RNPressable,
  ScrollView as RNScrollView,
  TouchableHighlight as RNTouchableHighlight,
  TextInput as RNTextInput,
  StyleSheet,
} from 'react-native';

// ── CSS Variable hook ────────────────────────────────────────────────────────
// On native, resolves a CSS custom property value at runtime.
// On web, returns a `var(…)` string for use inside inline styles.
export const useCSSVariable =
  process.env.EXPO_OS !== 'web'
    ? useFunctionalVariable
    : (variable: string) => `var(${variable})`;

// ── View ─────────────────────────────────────────────────────────────────────
export type ViewProps = React.ComponentProps<typeof RNView> & {
  className?: string;
};

export const View = (props: ViewProps) => {
  return useCssElement(RNView, props, { className: 'style' });
};
View.displayName = 'CSS(View)';

// ── Text ─────────────────────────────────────────────────────────────────────
export type TextProps = React.ComponentProps<typeof RNText> & {
  className?: string;
};

export const Text = (props: TextProps) => {
  return useCssElement(RNText, props, { className: 'style' });
};
Text.displayName = 'CSS(Text)';

// ── ScrollView ────────────────────────────────────────────────────────────────
export type ScrollViewProps = React.ComponentProps<typeof RNScrollView> & {
  className?: string;
  contentContainerClassName?: string;
};

export const ScrollView = (props: ScrollViewProps) => {
  // Cast component to any to avoid TS2590 (union type too complex) on RNScrollView's generics
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return useCssElement(RNScrollView as any, props as any, {
    className: 'style',
    contentContainerClassName: 'contentContainerStyle',
  });
};
ScrollView.displayName = 'CSS(ScrollView)';

// ── Pressable ─────────────────────────────────────────────────────────────────
export type PressableProps = React.ComponentProps<typeof RNPressable> & {
  className?: string;
};

export const Pressable = (props: PressableProps) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return useCssElement(RNPressable as any, props as any, { className: 'style' });
};
Pressable.displayName = 'CSS(Pressable)';

// ── TextInput ─────────────────────────────────────────────────────────────────
export type TextInputProps = React.ComponentProps<typeof RNTextInput> & {
  className?: string;
};

export const TextInput = (props: TextInputProps) => {
  return useCssElement(RNTextInput, props, { className: 'style' });
};
TextInput.displayName = 'CSS(TextInput)';

// ── TouchableHighlight ────────────────────────────────────────────────────────
// Extracts `underlayColor` from the flattened style before forwarding,
// because RNTouchableHighlight expects it as a separate prop.
function _TouchableHighlightBase(
  props: React.ComponentProps<typeof RNTouchableHighlight>,
) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { underlayColor, ...style } = (StyleSheet.flatten(props.style) || {}) as any;
  return (
    <RNTouchableHighlight
      underlayColor={underlayColor as string | undefined}
      {...props}
      style={style}
    />
  );
}

export type TouchableHighlightProps =
  React.ComponentProps<typeof RNTouchableHighlight> & { className?: string };

export const TouchableHighlight = (props: TouchableHighlightProps) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return useCssElement(_TouchableHighlightBase as any, props as any, { className: 'style' });
};
TouchableHighlight.displayName = 'CSS(TouchableHighlight)';

// ── AnimatedScrollView ────────────────────────────────────────────────────────
export type AnimatedScrollViewProps = React.ComponentProps<
  typeof Animated.ScrollView
> & {
  className?: string;
  contentContainerClassName?: string;
};

export const AnimatedScrollView = (props: AnimatedScrollViewProps) => {
  // Cast component to any to avoid TS2590 (union type too complex) on Animated.ScrollView's generics
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return useCssElement(Animated.ScrollView as any, props as any, {
    className: 'style',
    contentContainerClassName: 'contentContainerStyle',
  });
};
AnimatedScrollView.displayName = 'CSS(AnimatedScrollView)';

// ── Animated.View ─────────────────────────────────────────────────────────────
export type AnimatedViewProps = React.ComponentProps<typeof Animated.View> & {
  className?: string;
};

export const AnimatedView = (props: AnimatedViewProps) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return useCssElement(Animated.View as any, props as any, { className: 'style' });
};
AnimatedView.displayName = 'CSS(AnimatedView)';

// ── Link ─────────────────────────────────────────────────────────────────────
export const Link = (
  props: React.ComponentProps<typeof RouterLink> & { className?: string },
) => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return useCssElement(RouterLink as any, props as any, { className: 'style' });
};
Link.displayName = 'CSS(Link)';
Link.Trigger = RouterLink.Trigger;
Link.Menu = RouterLink.Menu;
Link.MenuAction = RouterLink.MenuAction;
Link.Preview = RouterLink.Preview;
