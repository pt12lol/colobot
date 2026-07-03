/*
 * This file is part of the Colobot: Gold Edition source code
 * Copyright (C) 2001-2023, Daniel Roux, EPSITEC SA & TerranovaTeam
 * http://epsitec.ch; http://colobot.info; http://github.com/colobot
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see http://gnu.org/licenses
 */

#include "ui/screen/screen.h"

#include "app/app.h"

#include "common/version.h"
#include "common/build_stamp.h" // DEBUG | DEVELOPMENT | REMOVEME

#include "graphics/engine/engine.h"

#include "level/robotmain.h"

#include "ui/controls/interface.h"
#include "ui/controls/label.h"
#include "ui/controls/window.h"

namespace Ui
{

CScreen::CScreen()
{
    m_main       = CRobotMain::GetInstancePointer();
    m_interface  = m_main->GetInterface();
    m_app        = CApplication::GetInstancePointer();
    m_eventQueue = m_app->GetEventQueue();
    m_engine     = Gfx::CEngine::GetInstancePointer();
    m_sound      = m_app->GetSound();
}

CScreen::~CScreen()
{
}

void CScreen::SetBackground(const std::string& filename, bool scaled)
{
    m_engine->SetBackground(filename,
            Gfx::Color(0.0f, 0.0f, 0.0f, 0.0f),
            Gfx::Color(0.0f, 0.0f, 0.0f, 0.0f),
            Gfx::Color(0.0f, 0.0f, 0.0f, 0.0f),
            Gfx::Color(0.0f, 0.0f, 0.0f, 0.0f),
            true, scaled);
    m_engine->SetBackForce(true);
}

void CScreen::CreateVersionDisplay()
{
    CWindow* pw = static_cast<CWindow*>(m_interface->SearchControl(EVENT_WINDOW5));
    if (pw != nullptr)
    {
        Math::Point pos, ddim;

        pos.x  = 540.0f/640.0f;
        pos.y  =   9.0f/480.0f;
        ddim.x =  90.0f/640.0f;
        ddim.y =  10.0f/480.0f;
        CLabel* pl = pw->CreateLabel(pos, ddim, 0, EVENT_LABEL1, COLOBOT_VERSION_DISPLAY);
        pl->SetFontType(Gfx::FONT_STUDIO);
        pl->SetFontSize(9.0f);

        // DEBUG | DEVELOPMENT | REMOVEME
        // Build timestamp (bottom-left), regenerated on every build so it's easy
        // to confirm a fresh binary is running after build-and-install.
        Math::Point spos, sdim;
        spos.x =  10.0f/640.0f;
        spos.y =   7.0f/480.0f;
        sdim.x = 200.0f/640.0f;
        sdim.y =  28.0f/480.0f;
        // Opaque background so the text stays readable over busy menu artwork.
        pw->CreateGroup(spos, sdim, 1, EVENT_LABEL3);
        CLabel* sl = pw->CreateLabel(spos, sdim, 0, EVENT_LABEL2, std::string("build ") + COLOBOT_BUILD_STAMP);
        sl->SetFontType(Gfx::FONT_STUDIO);
        sl->SetFontSize(9.0f);
        // DEBUG | DEVELOPMENT | REMOVEME (end)
    }
}

} // namespace Ui
