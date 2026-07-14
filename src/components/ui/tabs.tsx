import * as React from "react";
import * as TabsPrimitive from "@radix-ui/react-tabs";

import { cn } from "@/lib/utils";

const Tabs = TabsPrimitive.Root;

const TabsList = React.forwardRef<
  React.ElementRef<typeof TabsPrimitive.List>,
  React.ComponentPropsWithoutRef<typeof TabsPrimitive.List>
>(({ className, ...props }, ref) => (
  <TabsPrimitive.List
    ref={ref}
    className={cn(
      // min-h-10 (not h-10) so TabsList with wrapping grid layouts
      // (e.g. grid grid-cols-2 sm:grid-cols-4 on mobile) can grow to 2 rows
      // instead of overflowing into the content below.
      // Session B : habillage Y2K (fond lavande, coins arrondis 2xl, liseré rose)
      "inline-flex min-h-10 items-center justify-center rounded-2xl bg-jolene-cloud dark:bg-muted border border-jolene-rose-200/60 dark:border-border p-1 text-muted-foreground",
      className,
    )}
    {...props}
  />
));
TabsList.displayName = TabsPrimitive.List.displayName;

const TabsTrigger = React.forwardRef<
  React.ElementRef<typeof TabsPrimitive.Trigger>,
  React.ComponentPropsWithoutRef<typeof TabsPrimitive.Trigger>
>(({ className, ...props }, ref) => (
  <TabsPrimitive.Trigger
    ref={ref}
    className={cn(
      // Onglet actif : gradient rose→mauve Y2K + texte blanc (au lieu du blanc/gris
      // shadcn). Valeur arbitraire : .bg-gradient-hero (index.css hors @layer) ne
      // génère pas de variante data-[state=active].
      "inline-flex min-h-[44px] items-center justify-center whitespace-nowrap rounded-xl px-3 py-1.5 text-sm font-medium ring-offset-background transition-all data-[state=active]:bg-[linear-gradient(135deg,hsl(var(--jolene-rose-500)),hsl(var(--jolene-mauve-500)))] data-[state=active]:text-white data-[state=active]:shadow-md focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50",
      className,
    )}
    {...props}
  />
));
TabsTrigger.displayName = TabsPrimitive.Trigger.displayName;

const TabsContent = React.forwardRef<
  React.ElementRef<typeof TabsPrimitive.Content>,
  React.ComponentPropsWithoutRef<typeof TabsPrimitive.Content>
>(({ className, ...props }, ref) => (
  <TabsPrimitive.Content
    ref={ref}
    className={cn(
      "mt-2 ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2",
      className,
    )}
    {...props}
  />
));
TabsContent.displayName = TabsPrimitive.Content.displayName;

export { Tabs, TabsList, TabsTrigger, TabsContent };
