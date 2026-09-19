/**
 * WORKFLOW OF THIS FILE:
 * 1. Root of the desktop UI: maps screen ids to components.
 * 2. Wraps every screen in a PageTransition for smooth fade animations.
 * 3. Registers global keyboard shortcuts: Ctrl+S (send), Ctrl+R (receive).
 * 4. Global watchers: incoming offer jumps to Receive, transfer start jumps
 *    to Progress while on Home.
 */
import { useEffect, type ComponentType } from 'react'
import { useNav, type Screen } from './state/nav'
import { ConnectScreen } from './screens/ConnectScreen'
import { HomeScreen } from './screens/HomeScreen'
import { SendScreen } from './screens/SendScreen'
import { ReceiveScreen } from './screens/ReceiveScreen'
import { ProgressScreen } from './screens/ProgressScreen'
import { CompleteScreen } from './screens/CompleteScreen'
import { TransfersScreen } from './screens/TransfersScreen'
import { SettingsScreen } from './screens/SettingsScreen'
import { Sidebar } from './components/Sidebar'
import { PageTransition } from './components/PageTransition'

const SCREENS: Record<Screen, ComponentType> = {
  connect: ConnectScreen,
  home: HomeScreen,
  send: SendScreen,
  receive: ReceiveScreen,
  progress: ProgressScreen,
  complete: CompleteScreen,
  transfers: TransfersScreen,
  settings: SettingsScreen,
}

export default function App() {
  const screen = useNav((s) => s.screen)
  const go = useNav((s) => s.go)
  const CurrentScreen = SCREENS[screen]

  // Global keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's') {
        e.preventDefault()
        go('send')
      }
      if ((e.ctrlKey || e.metaKey) && e.key === 'r') {
        e.preventDefault()
        go('receive')
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [go])

  // Global navigation watchers
  useEffect(() => {
    if (!window.flova) return
    const offOffer = window.flova.onIncomingOffer(() => {
      const nav = useNav.getState()
      if (nav.screen === 'home') nav.go('receive')
    })
    const offStart = window.flova.onFileTransferStart(() => {
      const nav = useNav.getState()
      if (nav.screen === 'home') nav.go('progress')
    })
    return () => { offOffer(); offStart() }
  }, [])

  if (screen === 'connect') return <ConnectScreen />

  return (
    <div className="flex h-full">
      <Sidebar />
      <main className="flex flex-1 justify-center overflow-auto bg-canvas">
        <PageTransition screenKey={screen}>
          <CurrentScreen />
        </PageTransition>
      </main>
    </div>
  )
}