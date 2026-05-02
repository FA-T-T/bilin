import { createBrowserRouter } from "react-router-dom";

import { AppLayout } from "./components/AppLayout";
import { LibraryDetailPage } from "./pages/LibraryDetailPage";
import { LibraryHomePage } from "./pages/LibraryHomePage";
import { ReaderPage } from "./pages/ReaderPage";
import { SettingsPage } from "./pages/SettingsPage";

export const router = createBrowserRouter([
  {
    path: "/",
    element: <AppLayout />,
    children: [
      { index: true, element: <LibraryHomePage /> },
      { path: "libraries/:libraryId", element: <LibraryDetailPage /> },
      { path: "articles/:articleId", element: <ReaderPage /> },
      { path: "settings", element: <SettingsPage /> }
    ]
  }
]);
