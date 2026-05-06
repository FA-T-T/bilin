import { createBrowserRouter } from "react-router-dom";
import { lazy, Suspense, type ComponentType } from "react";

import { AppLayout } from "./components/AppLayout";
import { RouteFallback } from "./components/RouteFallback";

const LibraryHomePage = lazy(() =>
  import("./pages/LibraryHomePage").then((module) => ({ default: module.LibraryHomePage }))
);
const LibraryDetailPage = lazy(() =>
  import("./pages/LibraryDetailPage").then((module) => ({ default: module.LibraryDetailPage }))
);
const ReaderPage = lazy(() =>
  import("./pages/ReaderPage").then((module) => ({ default: module.ReaderPage }))
);
const SettingsPage = lazy(() =>
  import("./pages/SettingsPage").then((module) => ({ default: module.SettingsPage }))
);

function routeElement(Page: ComponentType) {
  return (
    <Suspense fallback={<RouteFallback />}>
      <Page />
    </Suspense>
  );
}

export const router = createBrowserRouter([
  {
    path: "/",
    element: <AppLayout />,
    children: [
      { index: true, element: routeElement(LibraryHomePage) },
      { path: "libraries/:libraryId", element: routeElement(LibraryDetailPage) },
      { path: "articles/:articleId", element: routeElement(ReaderPage) },
      { path: "settings", element: routeElement(SettingsPage) }
    ]
  }
]);
