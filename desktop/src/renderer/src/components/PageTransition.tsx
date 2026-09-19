/**
 * WORKFLOW OF THIS FILE:
 * 1. Wraps every screen with a fade + slide-up animation.
 * 2. When the child key changes, the old screen fades out and the new one
 *    fades in, giving smooth transitions between all app screens.
 * 3. Uses pure CSS animations (no external library needed).
 */
import { ReactNode } from 'react'

interface Props {
  children: ReactNode
  screenKey: string
}

export function PageTransition({ children, screenKey }: Props) {
  return (
    <div key={screenKey} className="page-enter">
      {children}
    </div>
  )
}