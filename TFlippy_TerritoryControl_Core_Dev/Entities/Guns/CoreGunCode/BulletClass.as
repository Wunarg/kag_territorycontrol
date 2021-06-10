//////////////////////////////////////////////////////
//
//  BulletClass.as - Vamist
//
//  CORE FILE
//  
//  A bit messy, stuff gets removed and added as time 
//  goes on. Handles the bullet class, what it hits
//  onTick, onRender etc
//
//  Try not poke around here unless you need to
//  Some code here is messy
//

#include "BulletCase.as";
#include "Recoil.as";
#include "BulletParticle.as";
#include "Knocked.as";
#include "GunCommon.as";
#include "DeityCommon.as";

const SColor trueWhite = SColor(255,255,255,255);
Driver@ PDriver = getDriver();
const int ScreenX = getDriver().getScreenWidth();
const int ScreenY = getDriver().getScreenWidth();

namespace BulletRender
{
	Vertex[] v_r_bullet;
	Vertex[] v_r_fade;
	Vertex[] v_r_reloadBox;
	string[] textureNames;

	void Reset()
	{
		//v_r_bullet.clear();
		//v_r_fade.clear();
	}

	void Draw()
	{
		BulletGrouped.AddToVertex(); // Fill up v_r_bullets

		/*for (int i = 0; i < v_r_bullet.length; i+= 4)
		{
			Vertex[] bulletVertex = {v_r_bullet[i], v_r_bullet[i+1], v_r_bullet[i+2], v_r_bullet[i+3]};
			string texture = textureNames[i/4];
			Render::RawQuads(texture, bulletVertex);
		}*/

		CRules@ rules = getRules();

		string[]@ vertex_book;
		rules.get("VertexBook", @vertex_book);

		for (int a = 0; a < vertex_book.length(); a++)
		{
			Vertex[]@ bulletVertex;
			string texture = vertex_book[a];
			rules.get(texture, @bulletVertex);
			
			// Sending empty vertex just eats performance because engine does not check :)
			if (bulletVertex.length() < 1)
				continue;

			Render::RawQuads(texture, bulletVertex);

			bulletVertex.clear();
		}
		

		if (g_debug == 0) // useful for lerp testing
		{
			v_r_bullet.clear();
		}
	}
}

class BulletObj
{
	CBlob@ hoomanShooter;
	CBlob@ gunBlob;

	BulletFade@ Fade;

	Vec2f CurrentVelocity;
	Vec2f LastLerpedPos;
	Vec2f CurrentPos;
	Vec2f BulletGrav;
	Vec2f OldPos;
	Vec2f Gravity;
	bool FacingLeft;

	f32 StartingAimAngle;
	f32 Angle;

	u8 Speed;
	s8 TimeLeft;

	BulletObj(CBlob@ humanBlob, CBlob@ gun, f32 angle, Vec2f pos)
	{
		@hoomanShooter = humanBlob;
		@gunBlob = gun;

		GunSettings@ settings;
		gun.get("gun_settings", @settings);

		StartingAimAngle = angle;
		CurrentPos = pos;

		BulletGrav = settings.B_GRAV;
		FacingLeft = gun.isFacingLeft();

		TimeLeft = settings.B_TTL;
		Speed = settings.B_SPEED;

		OldPos = CurrentPos;
		LastLerpedPos = CurrentPos;

		//@Fade = BulletGrouped.addFade(CurrentPos);
	}

	bool onFakeTick(CMap@ map)
	{
		// Kill bullet at start of new tick (we don't instantly remove it so client can render it going splat)
		TimeLeft--;
		if (TimeLeft == 0)
		{
			return true;
		}

		// Use the last lerp position to start from (so if client drops a frame, it still appears smooth)
		OldPos = LastLerpedPos;

		Gravity -= BulletGrav;

		// Direction shittery
		Vec2f dir = Vec2f((FacingLeft ? -1 : 1), 0.0f).RotateBy(StartingAimAngle);
		CurrentPos = ((dir * Speed) - (Gravity * Speed)) + CurrentPos;
		CurrentVelocity = CurrentPos - OldPos;
		Angle = -CurrentVelocity.getAngleDegrees();

		bool endBullet = false;
		HitInfo@[] list;
		if (map.getHitInfosFromRay(OldPos, Angle, CurrentVelocity.Length(), hoomanShooter, @list))
		{
			GunSettings@ settings;
			gunBlob.get("gun_settings", @settings);

			f32 ammotype = settings.B_TYPE;
			f32 damage = settings.B_DAMAGE;

			//Increase damage if hooman blob is a follower of the swaggy laggy
			if (hoomanShooter.get_u8("deity_id") == Deity::swaglag)
			{
				CBlob@ altar = getBlobByName("altar_swaglag");
				if (altar !is null)
				{
					damage *= 1.00f + Maths::Min(altar.get_f32("deity_power") * 0.01f, 2.00f);
				}
			}

			const string S_FLESH_HIT  = gunBlob.exists("CustomSoundFlesh")  ? gunBlob.get_string("CustomSoundFlesh")  : "BulletImpact.ogg";
			const string S_OBJECT_HIT = gunBlob.exists("CustomSoundObject") ? gunBlob.get_string("CustomSoundObject") : "BulletImpact.ogg";

			bool breakLoop = false;

			for (int a = 0; a < list.length(); a++)
			{
				HitInfo@ hit = list[a];
				Vec2f hitpos = hit.hitpos;
				CBlob@ blob = @hit.blob;
				if (blob !is null)
				{
					int hash = blob.getName().getHash();
					switch (hash)
					{
						case 804095823: // platform
						case 377147311: // iron platform
						{
							if (CollidesWithPlatform(blob, CurrentVelocity))
							{
								CurrentPos = hitpos;
								breakLoop = true;

								if (isClient())
								{
									Sound::Play(S_OBJECT_HIT, CurrentPos, 1.5f);
								}
								if (isServer())
								{
									hoomanShooter.server_Hit(blob, CurrentPos, CurrentVelocity, damage, ammotype); 
								}
							}
						}
						break;

						default:
						{
							//print(blob.getName() + '\n'+blob.getName().getHash()); //useful for debugging new tiles to hit

							if (blob.hasTag("flesh") || blob.isCollidable() || blob.hasTag("vehicle"))
							{
								if (blob.getTeamNum() == gunBlob.getTeamNum() && (blob.hasTag("flesh") || blob.hasTag("vehicle"))) continue;
								else if (blob.hasTag("weapon") || blob.hasTag("dead") || blob.hasTag("invincible")) continue;
								else if (blob.getName() == "iron_halfblock" || blob.getName() == "stone_halfblock") continue;

								CurrentPos = hitpos;

								if (isServer())
								{
									if (blob.hasTag("door")) damage *= 1.5f;
									hoomanShooter.server_Hit(blob, CurrentPos, CurrentVelocity / 2, damage, ammotype);
									gunBlob.server_Hit(blob, CurrentPos, CurrentVelocity / 2, 0.0f, ammotype, false); //For calling onHitBlob

									if (blob.hasTag("flesh") && gunBlob.exists("CustomKnock"))
									{
										SetKnocked(blob, gunBlob.get_u8("CustomKnock"));
									}

									CPlayer@ p = hoomanShooter.getPlayer();
									if (p !is null)
									{
										if (gunBlob.exists("CustomCoinFlesh"))
										{
											if (blob.hasTag("player")) p.server_setCoins(p.getCoins() + gunBlob.get_u32("CustomCoinFlesh"));
										}
										if (gunBlob.exists("CustomCoinObject"))
										{
											if (blob.hasTag("vehicle")) p.server_setCoins(p.getCoins() + gunBlob.get_u32("CustomCoinObject"));
										}
									}
								}
								if (isClient())
								{
									Sound::Play(S_FLESH_HIT, CurrentPos, 1.5f);
								}

								breakLoop = true;
							}
						}
					}

					if (breakLoop)//So we can break while inside the switch
					{
						endBullet = true;
						break;
					}
				}
				else
				{ 
					if (isServer())
					{
						Tile tile = map.getTile(hitpos);
						if (gunBlob.exists("CustomPenetration"))
						{
							for (int i = 0; i < gunBlob.get_u8("CustomPenetration"); i++)
							{
								map.server_DestroyTile(hitpos, 1.0f);
							}
						}
						else
						{
							map.server_DestroyTile(hitpos, 1.0f);
						}
					}

					if (isClient())
					{
						Sound::Play(S_OBJECT_HIT, hitpos, 1.5f);
					}

					CurrentPos = hitpos;
					ParticleBullet(CurrentPos, CurrentVelocity);
					endBullet = true;
				}
			}
		}

		if (endBullet)
		{
			TimeLeft = 1;
		}
		return false;
	}

	void JoinQueue(CRules@ rules) // Every bullet gets forced to join the queue in onRenders, so we use this to calc to position
	{
		// Are we on the screen?
		const Vec2f xLast = PDriver.getScreenPosFromWorldPos(OldPos);
		const Vec2f xNew  = PDriver.getScreenPosFromWorldPos(CurrentPos);
		if (!(xNew.x > 0 && xNew.x < ScreenX)) // Is our main position still on screen?
		{
			if (!(xLast.x > 0 && xLast.x < ScreenX)) // Was our last position on screen?
			{
				return; // No, lets not stay here then
			}
		}

		// Lerp
		Vec2f newPos = Vec2f_lerp(OldPos, CurrentPos, FRAME_TIME);
		LastLerpedPos = newPos;

		const f32 B_LENGTH = gunBlob.get_f32("CustomBulletLength");
		const f32 B_WIDTH  = gunBlob.get_f32("CustomBulletWidth");

		Vec2f topLeft  = Vec2f(newPos.x - B_WIDTH, newPos.y - B_LENGTH);
		Vec2f topRight = Vec2f(newPos.x - B_WIDTH, newPos.y + B_LENGTH);
		Vec2f botLeft  = Vec2f(newPos.x + B_WIDTH, newPos.y - B_LENGTH);
		Vec2f botRight = Vec2f(newPos.x + B_WIDTH, newPos.y + B_LENGTH);

		// Rotate the sprite to be in the correct pos
		f32 angle = Angle - 90;

		botLeft.RotateBy( angle, newPos);
		botRight.RotateBy(angle, newPos);
		topLeft.RotateBy( angle, newPos);
		topRight.RotateBy(angle, newPos);   

		/*if(FacingLeft)
		{
			Fade.JoinQueue(TopLeft,TopRight);
		}
		else
		{
			//Fade.JoinQueue(newPos,BotRight);
		}*/
		
		Vertex[]@ bullet_vertex;
		rules.get(gunBlob.get_string("CustomBullet"), @bullet_vertex);

		bullet_vertex.push_back(Vertex(topLeft.x,  topLeft.y,  0, 0, 0, trueWhite)); // top left
		bullet_vertex.push_back(Vertex(topRight.x, topRight.y, 0, 1, 0, trueWhite)); // top right
		bullet_vertex.push_back(Vertex(botRight.x, botRight.y, 0, 1, 1, trueWhite)); // bot right
		bullet_vertex.push_back(Vertex(botLeft.x,  botLeft.y,  0, 0, 1, trueWhite)); // bot left
	}
}

class BulletHolder
{
	BulletObj[] bullets;
	BulletFade[] fade;
	PrettyParticle@[] PParticles;
	Recoil@ localRecoil;
	BulletHolder(){}

	void FakeOnTick(CRules@ this)
	{
		CMap@ map = getMap();
		for (int a = 0; a < bullets.length(); a++)
		{
			BulletObj@ bullet = bullets[a];
			if (bullet.onFakeTick(map))
			{
				bullets.erase(a);
				//BulletRender::Erase(a);
				a--;
			}
		}
		//print(bullets.length() + '');

		for (int a = 0; a < PParticles.length(); a++)
		{
			if (PParticles[a].ttl == 0)
			{
				PParticles.erase(a);
				a--;
				continue;
			}
			PParticles[a].FakeTick();
		}

		if (localRecoil !is null)
		{
			if (localRecoil.TimeToNormal < 1)
			{
				@localRecoil = null;
			}
			else
			{
				localRecoil.onFakeTick();
			}
		}

		/*for(int a = 0; a < recoil.length(); a++)    
		{
			Recoil@ coil = recoil[a];
			if(coil.TimeToNormal < 1)
			{
				recoil.removeAt(a);
				continue;
			}
			else
			{
				coil.onFakeTick();
			}
		}*/
	}

	BulletFade addFade(Vec2f spawnPos)
	{
		BulletFade@ fadeToAdd = BulletFade(spawnPos);
		fade.push_back(fadeToAdd);
		return fadeToAdd; 
	}

	void addNewParticle(CParticle@ p,const u8 type)
	{
		PParticles.push_back(PrettyParticle(p,type));
	}

	void AddToVertex()
	{
		CRules@ rules = getRules();
		for (int a = 0; a < bullets.length(); a++)
		{
			bullets[a].JoinQueue(rules);
		}

		/*for(int a = 0; a < fade.length(); a++)
		{
			if(fade[a].TimeLeft < 1)
			{
				fade.removeAt(a);
				continue;
			}
			//fade[a].JoinQueue();
		}*/
	}

	void NewRecoil(Recoil@ this)
	{
		@localRecoil = this;
	}

	void AddNewObj(BulletObj@ this)
	{
		CMap@ map = getMap();
		this.onFakeTick(map);
		bullets.push_back(this);
	}

	void Clean()
	{
		bullets.clear();
	}

	int ArrayCount()
	{
		return bullets.length();
	}
}

const bool CollidesWithPlatform(CBlob@ blob, const Vec2f velocity) // Stolen from rock.as
{
	const f32 platform_angle = blob.getAngleDegrees();
	Vec2f direction = Vec2f(0.0f, -1.0f);
	direction.RotateBy(platform_angle);
	const float velocity_angle = direction.AngleWith(velocity);

	return !(velocity_angle > -90.0f && velocity_angle < 90.0f);
}
