// Copyright Brio / Wade Williams. All rights reserved.

#include "MarigoldRTXSettings.h"
#include "MarigoldRTX.h"
#include "DynamicRHI.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "HAL/IConsoleManager.h"

namespace
{
	const TCHAR* RTXConfigSection = TEXT("/Script/MarigoldRTX.MarigoldRTXSettings");
	const TCHAR* RTXConfigKey = TEXT("RequestedTier");
	// true = the user picked the tier (settings menu / console); false = the
	// first-boot automatic default.
	const TCHAR* RTXUserChosenKey = TEXT("bUserChosen");
	// Set after a crash: the automatic default never re-arms on its own.
	const TCHAR* RTXCrashLockoutKey = TEXT("bCrashLockout");
	// Project-level RT support kill switch, layered into Saved/Config Engine.ini.
	const TCHAR* RendererSection = TEXT("/Script/Engine.RendererSettings");

	bool IsStrongRTXAdapter()
	{
		const FString Adapter = GRHIAdapterName;
		return Adapter.Contains(TEXT("RTX 50")) || Adapter.Contains(TEXT("RTX 40"));
	}

	void SetProjectRayTracingForNextBoot(bool bEnable)
	{
		if (!GConfig)
		{
			return;
		}
		GConfig->SetString(RendererSection, TEXT("r.RayTracing"), bEnable ? TEXT("True") : TEXT("False"), GEngineIni);
		GConfig->Flush(false, GEngineIni);
	}
}

bool UMarigoldRTXSettings::IsRayTracingSupported()
{
	// THE guard. Plain bool global, safe to read any time after RHI init;
	// false until the RHI says otherwise. No RT call may happen unless this
	// returns true.
	return GRHISupportsRayTracing;
}

bool UMarigoldRTXSettings::IsRayTracingCompiledIn()
{
	// r.RayTracing is read-only after startup: its value is what the renderer
	// was initialized with.
	if (IConsoleVariable* Var = IConsoleManager::Get().FindConsoleVariable(TEXT("r.RayTracing")))
	{
		return Var->GetInt() != 0;
	}
	return false;
}

bool UMarigoldRTXSettings::IsRayTracingUsable()
{
	return IsRayTracingSupported() && IsD3D12() && IsRayTracingCompiledIn();
}

bool UMarigoldRTXSettings::IsD3D12()
{
	if (GDynamicRHI == nullptr)
	{
		return false;
	}
	return FCString::Stricmp(GDynamicRHI->GetName(), TEXT("D3D12")) == 0;
}

void UMarigoldRTXSettings::ApplyTier(EMarigoldRTXTier NewTier)
{
	ApplyTierStatic(static_cast<int32>(NewTier));
	RequestedTier = NewTier;
	ActiveTier = IsRayTracingUsable() ? NewTier : EMarigoldRTXTier::Off;
}

void UMarigoldRTXSettings::ApplyTierStatic(int32 TierIndex)
{
	FMarigoldRTXModule::SetRTXTier(TierIndex);
}

void UMarigoldRTXSettings::ApplyTierStatic(EMarigoldRTXTier NewTier)
{
	ApplyTierStatic(static_cast<int32>(NewTier));
}

void UMarigoldRTXSettings::AutoDetectAndApply()
{
	AutoDetectAndApplyStatic();
	// Mirror the static result into this instance for Blueprint readers.
	const bool bUsable = IsRayTracingUsable();
	RequestedTier = bUsable ? EMarigoldRTXTier::ShadowsOnly : EMarigoldRTXTier::Off;
	ActiveTier = RequestedTier;
}

void UMarigoldRTXSettings::AutoDetectAndApplyStatic()
{
	// Blackwell safety: the editor runs DX11 by default, so this lands on
	// Off there. Only D3D12 game sessions with DXR hardware enable RT.
	if (IsRayTracingUsable())
	{
		UE_LOG(LogMarigoldRTX, Log, TEXT("Auto-detect: D3D12 + DXR present -> ShadowsOnly"));
		ApplyTierStatic(EMarigoldRTXTier::ShadowsOnly);
	}
	else
	{
		UE_LOG(LogMarigoldRTX, Log, TEXT("Auto-detect: no DXR on this RHI -> Off (shadow-map fallback)"));
		ApplyTierStatic(EMarigoldRTXTier::Off);
	}
}

FString UMarigoldRTXSettings::GetStatusString() const
{
	return FString::Printf(TEXT("Requested=%d Active=%d | %s"),
		static_cast<int32>(RequestedTier),
		static_cast<int32>(ActiveTier),
		*FMarigoldRTXModule::GetRTXStatus());
}

int32 UMarigoldRTXSettings::LoadRequestedTierStatic()
{
	int32 Saved = 0; // default Off — RT is explicit opt-in (887A002B history)
	if (GConfig)
	{
		GConfig->GetInt(RTXConfigSection, RTXConfigKey, Saved, GGameIni);
	}
	return FMath::Clamp(Saved, 0, 2);
}

void UMarigoldRTXSettings::SaveRequestedTierStatic(int32 TierIndex)
{
	if (GConfig)
	{
		GConfig->SetInt(RTXConfigSection, RTXConfigKey, FMath::Clamp(TierIndex, 0, 2), GGameIni);
		GConfig->Flush(false, GGameIni);
	}
	FMarigoldRTXModule::PublishRequestedTier(TierIndex);
}

void UMarigoldRTXSettings::RequestTierStatic(int32 TierIndex)
{
	// Explicit user choice (settings menu / console): it overrides the
	// automatic default and re-arms RT after a crash lockout.
	const int32 Clamped = FMath::Clamp(TierIndex, 0, 2);
	if (GConfig)
	{
		GConfig->SetBool(RTXConfigSection, RTXUserChosenKey, true, GGameIni);
		if (Clamped > 0)
		{
			GConfig->SetBool(RTXConfigSection, RTXCrashLockoutKey, false, GGameIni);
		}
	}
	SaveRequestedTierStatic(Clamped);
	if (Clamped > 0 && !IsRayTracingCompiledIn())
	{
		// A crash recovery switched project RT support off; turn it back on
		// for the next launch (it cannot be compiled in mid-session).
		SetProjectRayTracingForNextBoot(true);
		UE_LOG(LogMarigoldRTX, Warning,
			TEXT("Ray tracing support is not active this session. Tier %d is saved and takes effect after a RESTART."), Clamped);
	}
	ApplyTierStatic(Clamped);
	UE_LOG(LogMarigoldRTX, Log, TEXT("RTX tier explicitly requested by the user: %d (persisted)"), Clamped);
}

void UMarigoldRTXSettings::ApplyPersistedTierStatic()
{
	// Game sessions only (the module skips the hook in the editor).
	if (FMarigoldRTXModule::DidPreviousSessionCrash())
	{
		// CRASH GUARD: the last session died (887A002B or anything else).
		// Force Off, persist Off, lock out the automatic default, and disable
		// project RT support for the next boot (pure software Lumen).
		if (GConfig)
		{
			GConfig->SetBool(RTXConfigSection, RTXUserChosenKey, false, GGameIni);
			GConfig->SetBool(RTXConfigSection, RTXCrashLockoutKey, true, GGameIni);
		}
		SaveRequestedTierStatic(0);
		ApplyTierStatic(0);
		if (IsRayTracingCompiledIn())
		{
			SetProjectRayTracingForNextBoot(false);
		}
		UE_LOG(LogMarigoldRTX, Error, TEXT("************************************************************"));
		UE_LOG(LogMarigoldRTX, Error,
			TEXT("RT CRASH GUARD: the previous session did not exit cleanly%s."),
			FMarigoldRTXModule::DidPreviousRTSessionCrash() ? TEXT(" WHILE RAY TRACING WAS ON") : TEXT(""));
		UE_LOG(LogMarigoldRTX, Error,
			TEXT("Ray tracing forced OFF and saved as Off; it will not auto-enable again. Re-select it in Settings to opt back in."));
		UE_LOG(LogMarigoldRTX, Error, TEXT("************************************************************"));
		return;
	}

	int32 Saved = 0;
	const bool bHasSaved = GConfig && GConfig->GetInt(RTXConfigSection, RTXConfigKey, Saved, GGameIni);
	bool bUserChosen = false;
	bool bLockout = false;
	if (GConfig)
	{
		GConfig->GetBool(RTXConfigSection, RTXUserChosenKey, bUserChosen, GGameIni);
		GConfig->GetBool(RTXConfigSection, RTXCrashLockoutKey, bLockout, GGameIni);
	}
	const bool bVR = FParse::Param(FCommandLine::Get(), TEXT("vr"));
	const bool bUsable = IsRayTracingUsable();

	int32 Tier = FMath::Clamp(Saved, 0, 2);
	if (!bHasSaved)
	{
		// FIRST BOOT. Standing rule (MERGE_PROTOCOL.md / AI_COORDINATION.md,
		// 2026-10-23): RT tiers are explicit opt-in only — never auto-enabled
		// at startup on D3D12 (887A002B crash history on the RTX 5070 Ti).
		// The 2026-10-20 "flat PC + RTX 40/50 defaults to Full" path is
		// replaced by a log hint; the user opts in via Settings or marigold.rtx.
		Tier = 0;
		if (!bVR && !bLockout && bUsable && IsStrongRTXAdapter())
		{
			UE_LOG(LogMarigoldRTX, Log,
				TEXT("First boot on '%s' (flat PC): ray tracing is available but stays OFF until chosen in Settings (or 'marigold.rtx 1|2')."),
				*GRHIAdapterName);
		}
	}
	else if (bVR && !bUserChosen && Tier > 0)
	{
		UE_LOG(LogMarigoldRTX, Log, TEXT("VR session: the automatic RT default does not apply in VR — RT Off (pick it in Settings to opt in)."));
		Tier = 0;
	}

	FMarigoldRTXModule::PublishRequestedTier(bHasSaved ? Saved : Tier);
	ApplyTierStatic(Tier);
	UE_LOG(LogMarigoldRTX, Log,
		TEXT("Boot RTX: persisted=%d (user-chosen=%d, lockout=%d) VR=%d usable=%d -> tier %d | %s"),
		bHasSaved ? Saved : -1, bUserChosen ? 1 : 0, bLockout ? 1 : 0, bVR ? 1 : 0, bUsable ? 1 : 0,
		bUsable ? Tier : 0, *FMarigoldRTXModule::GetRTXStatus());
}
