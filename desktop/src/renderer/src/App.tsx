/**
 * WORKFLOW OF THIS FILE:
 * 1. Root of the desktop UI: maps screen ids to components.
 * 2. Global watchers: incoming offer jumps to Receive while on Home, and any
 *    transfer start jumps to Progress while on Home.
 * 3. History is rendered inside TransfersScreen, not as its own screen.
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
  const CurrentScreen = SCREENS[screen]

  useEffect(() => {
    const offOffer = window.flova?.onIncomingOffer(() => {
      const nav = useNav.getState()
      if (nav.screen === 'home') nav.go('receive')
    })
    const offStart = window.flova?.onFileTransferStart(() => {
      const nav = useNav.getState()
      if (nav.screen === 'home') nav.go('progress')
    })
    return () => {
      offOffer?.()
      offStart?.()
    }
  }, [])

  if (screen === 'connect') return <ConnectScreen />

  return (
    <div className="flex h-full">
      <Sidebar />
      <main className="flex flex-1 justify-center overflow-auto bg-canvas">
        <CurrentScreen />
      </main>
    </div>
  )
}