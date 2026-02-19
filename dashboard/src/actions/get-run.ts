"use server"

import { getRun } from "@/lib/db"
import type { Run } from "@/types"

export async function fetchRun(id: string): Promise<Run | null> {
  return getRun(id)
}
