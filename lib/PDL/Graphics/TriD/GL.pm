use strict;
use warnings;
no warnings 'redefine';
use OpenGL::Modern qw/
  glRotatef glTranslatef
  GL_LINE_STRIP GL_LINE_LOOP
  GL_MODELVIEW GL_PROJECTION
/;
use PDL::Core qw(barf);

{ package PDL::Graphics::TriD::Material;
use OpenGL::Modern qw(
  glMaterialfv_p
  GL_FRONT_AND_BACK GL_SHININESS GL_SPECULAR GL_AMBIENT GL_DIFFUSE
);
sub togl {
  my $this = shift;
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_SHININESS,$this->{Shine});
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_SPECULAR,@{$this->{Specular}});
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_AMBIENT,@{$this->{Ambient}});
  glMaterialfv_p(GL_FRONT_AND_BACK,GL_DIFFUSE,@{$this->{Diffuse}});
}
}

$PDL::Graphics::TriD::verbose //= 0;

{ package PDL::Graphics::TriD::Object;
sub togl_setup {
  print "togl_setup $_[0]\n" if $PDL::Graphics::TriD::verbose;
  $_->togl_setup for $_[0]->contained_objects;
}
sub togl { $_->togl for $_[0]->contained_objects }
}

sub PDL::Graphics::TriD::Graph::togl_setup {
  my ($this) = @_;
  $this->{Axis}{$_}->togl_setup for grep $_ ne "Default", keys %{$this->{Axis}};
  while (my ($series,$h) = each %{ $this->{Data} }) {
    for my $data (values %$h) {
      $data->togl_setup($this->get_points($series, $data));
    }
  }
}
sub PDL::Graphics::TriD::Graph::togl {
  my ($this) = @_;
  $this->{Axis}{$_}->togl for grep $_ ne "Default", keys %{$this->{Axis}};
  while (my ($series,$h) = each %{ $this->{Data} }) {
    for my $data (values %$h) {
      $data->togl($this->get_points($series, $data));
    }
  }
}

use POSIX qw//;
sub PDL::Graphics::TriD::Quaternion::togl {
  my($this) = @_;
  if(abs($this->[0]) == 1) { return ; }
  if(abs($this->[0]) >= 1) {
    $this->normalise;
  }
  glRotatef(2*POSIX::acos($this->[0])/3.14*180, @{$this}[1..3]);
}

##################################
# Graph Objects

{ package PDL::Graphics::TriD::Labels;
use OpenGL::Modern qw(
  glEnable glBlendFunc
  glDrawElements_c
  GL_BLEND GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA
  GL_TRIANGLES GL_UNSIGNED_INT
  GL_RGBA32F GL_RGBA
);
use PDL::Graphics::OpenGLQ;
my %FONT;
sub _font_setup {
  my ($fref) = @_;
  my ($texture, $rightbound, $orig) = gl_font_texture();
  $fref->{texture} = PDL::float(1,1,1,1) * $texture->dummy(0,1);
  my $widthpix = $rightbound->numdiff; $widthpix->slice('0') += 1;
  @{ $fref->{widthpix} } = $widthpix->list;
  $fref->{heightpix} = $texture->dim(1);
  $fref->{numchars} = my $numchars = $rightbound->nelem;
  $fref->{texwidthm1} = my $texwidthm1 = $texture->dim(0) - 1;
  $fref->{leftbound} = my $leftbound = $rightbound->rotate(1) + 1;
    $leftbound->slice('0') .= 0; $leftbound->set_datatype(PDL::float->enum);
  $fref->{rightbound} = $rightbound = $rightbound->float;
  $_ /= $texwidthm1 for $leftbound, $rightbound;
  @$fref{qw(xorig yorig)} = $orig->list;
  $fref->{texture} = PDL::float(1,1,1,1) * $texture->dummy(0,1);
  # 4 = top-left, bot-left, top-right, bot-right, triangle idx=012,213
  $fref->{idx} = PDL->new(PDL::ulong, [0,1,2], [2,1,3]);
  $fref->{texcoords} = my $texcoords = PDL->zeroes(PDL::float,2,4,$numchars);
  $texcoords->slice('(0),0:1') .= $leftbound->dummy(0,1);  # u of left
  $texcoords->slice('(0),2:3') .= $rightbound->dummy(0,1); # u of right
  $texcoords->slice('(1),0::2') .= 1;          # v of top, v bot=already 0
}
sub togl_setup {
  my ($this,$points) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  if (!keys %FONT) {
    _font_setup(\%FONT);
    $this->load_texture(font_id => $FONT{texture}, GL_RGBA32F, ($FONT{texture}->dims)[1,2], GL_RGBA);
    $FONT{font_id} = $this->{Impl}{font_id};
  } else {
    $this->{Impl}{font_id} = $FONT{font_id};
  }
  $points //= $this->{Points}; # as Labels is used in Graph
  my $numchars = $FONT{numchars};
  my $vert_template = PDL->new(PDL::float, [0,0,1], [0,0,0], [1,0,1], [1,0,0]);
  my $dwidth = $PDL::Graphics::TriD::Window::DEFAULT_WIDTH / 1.5;
  my $dheight = $PDL::Graphics::TriD::Window::DEFAULT_HEIGHT / 1.5;
  $vert_template *= PDL::float(1 / $dwidth, 1, $FONT{heightpix} / $dheight);
  my (@codes) = map [map ord, split //], @{ $this->{Strings} };
  my ($total_chars, @i, @v, @tc) = 0;
  for (0..$#codes) {
    my ($l, $point, $xoffset) = ($codes[$_], $points->dice_axis(1, $_), 0);
    for (0..$#$l) {
      my $c = $l->[$_];
      PDL::barf "Codepoint $c >= $numchars" if $c >= $numchars;
      my $thiswidth = $FONT{widthpix}[$c];
      push @i, $FONT{idx} + 4*$total_chars;
      push @v, $point + PDL::float($xoffset,0,0) + ($vert_template * PDL::float($thiswidth,1,1));
      push @tc, $FONT{texcoords}->slice(",,($c)");
      $xoffset += $thiswidth / $dwidth;
      $total_chars++;
    }
  }
  $this->{Impl}{idx} = PDL::cat(@i)->clump(1,2);
  $this->load_buffer(vert_buf => my $v = PDL::cat(@v)->clump(1,2));
  $this->load_buffer(texc_buf => my $tc = PDL::cat(@tc)->clump(1,2));
  $this->load_idx_buffer(indx_buf => $this->{Impl}{idx});
  $this->togl_unbind;
}
sub gdraw {
  my($this,$points) = @_;
  $this->togl_bind;
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDrawElements_c(GL_TRIANGLES, $this->{Impl}{idx}->nelem, GL_UNSIGNED_INT, 0);
  $this->togl_unbind;
}
}

my %mode2enum = (
  linestrip => GL_LINE_STRIP,
  lineloop => GL_LINE_LOOP,
);

{ package PDL::Graphics::TriD::GObject;
use OpenGL::Modern qw(
  glPushAttrib glPopAttrib
  glLineWidth glPointSize
  glLightfv_p glLightModeli
  glEnableClientState glDisableClientState
  glVertexPointer_c glColorPointer_c glTexCoordPointer_c glNormalPointer_c
  glEnable glDisable
  glGetIntegerv_p
  glGenBuffers_p glBindBuffer glDeleteBuffers_p glBufferData_c
  glGenTextures_p glBindTexture glDeleteTextures_p
  glTexImage2D_c glTexParameteri
  GL_VERTEX_ARRAY GL_COLOR_ARRAY GL_TEXTURE_COORD_ARRAY GL_NORMAL_ARRAY
  GL_LIGHTING_BIT GL_ENABLE_BIT GL_DEPTH_TEST GL_LIGHTING GL_LIGHT0
  GL_LIGHT_MODEL_TWO_SIDE GL_TRUE GL_POSITION
  GL_ARRAY_BUFFER GL_ARRAY_BUFFER_BINDING
  GL_ELEMENT_ARRAY_BUFFER GL_ELEMENT_ARRAY_BUFFER_BINDING
  GL_TEXTURE_MIN_FILTER GL_TEXTURE_MAG_FILTER
  GL_NEAREST GL_CLAMP_TO_EDGE GL_TEXTURE_WRAP_S GL_TEXTURE_WRAP_T
  GL_TEXTURE_2D GL_TEXTURE_BINDING_2D
  GL_FLOAT GL_STATIC_DRAW
);
sub load_buffer {
  my ($this, $idname, $pdl, $target, $usage) = @_;
  $target //= GL_ARRAY_BUFFER;
  $usage //= GL_STATIC_DRAW;
  my $id = $this->{Impl}{$idname} //= glGenBuffers_p(1);
  glBindBuffer($target, $id);
  # physicalise on nbytes not on second use so nbytes is correct
  glBufferData_c($target, $pdl->make_physical->nbytes, $pdl->address_data, $usage);
}
sub load_idx_buffer {
  my ($this, $idname, $pdl, $usage) = @_;
  $this->load_buffer($idname, $pdl, GL_ELEMENT_ARRAY_BUFFER, $usage);
}
sub load_texture {
  my ($this, $idname, $pdl, $iformat, $x, $y, $format, $type, $target) = @_;
  $type //= GL_FLOAT;
  $target //= GL_TEXTURE_2D;
  # ||= as only need one, even if re-setup
  glBindTexture($target, $this->{Impl}{$idname} ||= glGenTextures_p(1));
  glTexImage2D_c($target, 0, $iformat, $x, $y, 0, $format, $type, $pdl->make_physical->address_data);
  glTexParameteri($target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri($target, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri($target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri($target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}
sub togl_bind {
  my ($this) = @_;
  # font_id doesn't get deleted in DESTROY
  if (my ($id) = grep defined, @{ $this->{Impl} }{qw(tex_id font_id)}) {
    glBindTexture(GL_TEXTURE_2D, $id);
    glEnable(GL_TEXTURE_2D);
  }
  if (defined $this->{Impl}{vert_buf}) {
    glEnableClientState(GL_VERTEX_ARRAY);
    glBindBuffer(GL_ARRAY_BUFFER, $this->{Impl}{vert_buf});
    glVertexPointer_c(3, GL_FLOAT, 0, 0);
  }
  if (defined $this->{Impl}{color_buf}) {
    glEnableClientState(GL_COLOR_ARRAY);
    glBindBuffer(GL_ARRAY_BUFFER, $this->{Impl}{color_buf});
    glColorPointer_c(3, GL_FLOAT, 0, 0);
  }
  if (defined $this->{Impl}{texc_buf}) {
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glBindBuffer(GL_ARRAY_BUFFER, $this->{Impl}{texc_buf});
    glTexCoordPointer_c(2, GL_FLOAT, 0, 0);
  }
  if (defined $this->{Impl}{norm_buf}) {
    glEnableClientState(GL_NORMAL_ARRAY);
    glBindBuffer(GL_ARRAY_BUFFER, $this->{Impl}{norm_buf});
    glNormalPointer_c(GL_FLOAT, 0, 0);
  }
  if (defined $this->{Impl}{indx_buf}) {
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, $this->{Impl}{indx_buf}); # unbind the VAO before you unbind the Index Buffer
  }
}
sub togl_unbind {
  my ($this) = @_;
  glBindBuffer($_, 0) for GL_ARRAY_BUFFER, GL_ELEMENT_ARRAY_BUFFER;
  glDisableClientState(GL_VERTEX_ARRAY) if defined $this->{Impl}{vert_buf};
  glDisableClientState(GL_COLOR_ARRAY) if defined $this->{Impl}{color_buf};
  glDisableClientState(GL_TEXTURE_COORD_ARRAY) if defined $this->{Impl}{texc_buf};
  glDisableClientState(GL_NORMAL_ARRAY) if defined $this->{Impl}{norm_buf};
  if (defined $this->{Impl}{tex_id}) {
    glBindTexture(GL_TEXTURE_2D, 0);
    glDisable(GL_TEXTURE_2D);
  }
}
sub togl {
  my ($this, $points) = @_;
  print "togl $this\n" if $PDL::Graphics::TriD::verbose;
  glPushAttrib(GL_LIGHTING_BIT | GL_ENABLE_BIT);
  glLineWidth($this->{Options}{LineWidth} || 1);
  glPointSize($this->{Options}{PointSize} || 1);
  glEnable(GL_DEPTH_TEST);
  if ($this->{Options}{Lighting}) {
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE);
    glLightfv_p(GL_LIGHT0,GL_POSITION,1.0,1.0,1.0,0.0);
  } else {
    glDisable(GL_LIGHTING);
  }
  eval {
    $this->gdraw($points // $this->{Points});
  };
  { local $@; glPopAttrib(); }
  die if $@;
}
sub DESTROY {
  my ($this) = @_;
  print "DESTROY $this\n" if $PDL::Graphics::TriD::verbose;
  my $bound = glGetIntegerv_p(GL_ARRAY_BUFFER_BINDING);
  my @array_bufs = grep defined, @{ $this->{Impl} }{qw(vert_buf color_buf norm_buf texc_buf)};
  glBindBuffer(GL_ARRAY_BUFFER, 0) if grep $bound == $_, @array_bufs;
  $bound = glGetIntegerv_p(GL_ELEMENT_ARRAY_BUFFER_BINDING);
  my @elt_bufs = grep defined, @{ $this->{Impl} }{qw(indx_buf)};
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0) if grep $bound == $_, @elt_bufs;
  glDeleteBuffers_p(@array_bufs, @elt_bufs) if @array_bufs + @elt_bufs;
  if (defined(my $tex_id = $this->{Impl}{tex_id})) {
    glBindTexture(GL_TEXTURE_2D, 0) if glGetIntegerv_p(GL_TEXTURE_BINDING_2D) == $tex_id;
    glDeleteTextures_p($tex_id);
  }
}
}

{ package PDL::Graphics::TriD::GL::Primitive;
use OpenGL::Modern qw(glDrawArrays);
sub togl_setup {
  my ($this,$points) = @_;
  $points //= $this->{Points}; # as Lines is used in Graph
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  $this->load_buffer(vert_buf => $points);
  $this->load_buffer(color_buf => $this->{Colors});
  $this->togl_unbind;
}
sub gdraw {
  my($this,$points) = @_;
  $this->togl_bind;
  glDrawArrays($this->primitive, 0, $points->nelem / $points->dim(0));
  $this->togl_unbind;
}
}

unshift @PDL::Graphics::TriD::Points::ISA, qw(PDL::Graphics::TriD::GL::Primitive);
sub PDL::Graphics::TriD::Points::primitive {OpenGL::Modern::GL_POINTS}
unshift @PDL::Graphics::TriD::Lines::ISA, qw(PDL::Graphics::TriD::GL::Primitive);
sub PDL::Graphics::TriD::Lines::primitive {OpenGL::Modern::GL_LINES}

{ package PDL::Graphics::TriD::Spheres;
use OpenGL::Modern qw(glShadeModel GL_SMOOTH);
use PDL::Graphics::OpenGLQ;
my %SPHERE;
my @KEYS = qw(vertices normals idx);
sub togl_setup {
  my ($this,$points) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  if (!keys %SPHERE) {
    @SPHERE{@KEYS} = gl_sphere(0.025, 15, 15);
  }
  @{ $this->{Impl} }{@KEYS} = @SPHERE{@KEYS};
  $this->load_buffer(vert_buf => $this->{Impl}{vertices});
  $this->load_buffer(norm_buf => $this->{Impl}{normals});
  $this->togl_unbind;
}
sub gdraw {
  my($this,$points) = @_;
  $this->togl_bind;
  glShadeModel(GL_SMOOTH);
  PDL::gl_spheres($points, $this->{Impl}{idx});
  $this->togl_unbind;
}
}

{ package PDL::Graphics::TriD::Triangles;
use OpenGL::Modern qw(
  glShadeModel glColorMaterial glEnable glDisable
  glDrawElements_c
  GL_FLAT GL_SMOOTH GL_FRONT_AND_BACK GL_DIFFUSE GL_COLOR_MATERIAL
  GL_TRIANGLES GL_UNSIGNED_INT
);
sub togl_setup {
  my ($this,$points) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  $this->load_buffer(vert_buf => $points);
  $this->load_buffer(color_buf => $this->{Colors});
  $this->load_idx_buffer(indx_buf => $this->{Faceidx});
  $this->load_buffer(norm_buf => $this->{Normals}) if $this->{Options}{Shading} > 2;
  $this->togl_unbind;
}
sub gdraw {
  my ($this,$points) = @_;
  my $options = $this->{Options};
  my $shading = $options->{Shading};
  glShadeModel($shading == 1 ? GL_FLAT : GL_SMOOTH) if $shading;
  if ($shading > 2) {
    glColorMaterial(GL_FRONT_AND_BACK,GL_DIFFUSE);
    glEnable(GL_COLOR_MATERIAL);
  }
  $this->togl_bind;
  glDrawElements_c(GL_TRIANGLES, $this->{Faceidx}->nelem, GL_UNSIGNED_INT, 0);
  if ($shading > 2) {
    glDisable(GL_COLOR_MATERIAL);
  }
  $this->togl_unbind;
}
}

{ package PDL::Graphics::TriD::DrawMulti;
use OpenGL::Modern qw(glMultiDrawElements_c GL_UNSIGNED_INT);
sub togl_setup {
  my ($this,$points) = @_;
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  $this->load_buffer(vert_buf => $points);
  $this->load_buffer(color_buf => $this->{Colors});
  $this->load_idx_buffer(indx_buf => $this->{Indices});
  $this->togl_unbind;
  $this->{Impl}{Starts4} = $this->{Starts}->indx * PDL::Core::howbig(PDL::ulong->enum); # byte offset into GPU buffer, not elements
}
sub gdraw {
  my ($this,$points) = @_;
  my $mode = $mode2enum{$this->{Mode}} || PDL::barf "DrawMulti unknown mode";
  $this->togl_bind;
  # switch to glPrimitiveRestartindex when 3.1 available
  glMultiDrawElements_c($mode, $this->{Counts}->make_physical->address_data, GL_UNSIGNED_INT, $this->{Impl}{Starts4}->make_physical->address_data, $this->{Counts}->nelem);
  $this->togl_unbind;
}
}

# has a mode to face the display and take the entire window
{ package PDL::Graphics::TriD::Image;
use OpenGL::Modern qw(
  glMatrixMode glLoadIdentity glOrtho
  glDrawArrays
  GL_MODELVIEW GL_PROJECTION
  GL_TRIANGLE_STRIP GL_RGB
);
sub togl_setup {
  my ($this,$points) = @_;
  $points //= $this->{Points};
  print "togl_setup $this\n" if $PDL::Graphics::TriD::verbose;
  my ($p,$xd,$yd,$txd,$tyd) = $this->flatten(1); # do binary alignment
  $this->load_buffer(vert_buf => $points);
  # assume proportions could change each time
  my $texvert = PDL->new(PDL::float, [
    [$xd/$txd, 0],
    [$xd/$txd, $yd/$tyd],
    [0,0],
    [0, $yd/$tyd]
  ]);
  $this->load_buffer(texc_buf => $texvert);
  $this->load_texture(tex_id => $p, GL_RGB, $txd, $tyd, GL_RGB);
  $this->togl_unbind;
}
sub gdraw {
  my ($this,$points) = @_;
  $points //= $this->{Points};
  PDL::barf "Need 3,4 vert"
    if grep $_->dim(1) < 4 || $_->dim(0) != 3, $points;
  if ($this->{Options}{FullScreen}) {
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrtho(0,1,0,1,-1,1);
  }
  $this->togl_bind;
  glDrawArrays(GL_TRIANGLE_STRIP, 0, $points->nelem / $points->dim(0));
  $this->togl_unbind;
}
}

sub PDL::Graphics::TriD::SimpleController::togl {
	my($this) = @_;
	$this->{CRotation}->togl();
	glTranslatef(0,0,-$this->{CDistance});
	$this->{WRotation}->togl();
	glTranslatef(map {-$_} @{$this->{WOrigin}});
}

##############################################
# A window with mouse control over rotation.
package # hide from PAUSE
  PDL::Graphics::TriD::Window;

use OpenGL::Modern qw/
  glpSetAutoCheckErrors
  glPixelStorei glReadPixels_c
  glClear glClearColor glEnable
  glShadeModel glPushMatrix glPopMatrix glMatrixMode
  glPushAttrib glPopAttrib
  GL_UNPACK_ALIGNMENT GL_PACK_ALIGNMENT GL_RGB GL_UNSIGNED_BYTE
  GL_FLAT GL_NORMALIZE GL_MODELVIEW
  GL_COLOR_BUFFER_BIT GL_DEPTH_BUFFER_BIT
  GL_TRANSFORM_BIT
/;

use base qw/PDL::Graphics::TriD::Object/;
use fields qw/Ev Width Height Interactive _GLObject
              _ViewPorts _CurrentViewPort /;

sub gdriver {
  my($this, $options) = @_;
  print "GL gdriver...\n" if $PDL::Graphics::TriD::verbose;
  if(defined $this->{_GLObject}){
    print "WARNING: Graphics Driver already defined for this window \n";
    return;
  }
  my $window_type = $ENV{POGL_WINDOW_TYPE} || 'glfw';
  my $gl_class = $window_type =~ /x11/i ? 'PDL::Graphics::TriD::GL::GLX' :
    $window_type =~ /glut/i ? 'PDL::Graphics::TriD::GL::GLUT' :
    'PDL::Graphics::TriD::GL::GLFW';
  (my $file = $gl_class) =~ s#::#/#g; require "$file.pm";
  print "gdriver: Calling $gl_class(@$options{qw(width height)})\n" if $PDL::Graphics::TriD::verbose;
  $this->{_GLObject} = $gl_class->new($options, $this);
  $this->{_GLObject}->set_window;
  print "gdriver: Calling glClearColor...\n" if $PDL::Graphics::TriD::verbose;
  glClearColor(0,0,0,1);
  glShadeModel(GL_FLAT);
  glEnable(GL_NORMALIZE);
  print "STARTED OPENGL!\n" if $PDL::Graphics::TriD::verbose;
  if($PDL::Graphics::TriD::offline) {
    $this->doconfig($options->{width}, $options->{height});
  }
  return 1;  # Interactive Window
}

sub ev_defaults{
  return {	ConfigureNotify => \&doconfig,
				MotionNotify => \&domotion,
			}
}

sub reshape {
	my($this,$x,$y) = @_;
	my $pw = $this->{Width};
	my $ph = $this->{Height};
	$this->{Width} = $x; $this->{Height} = $y;
	for my $vp (@{$this->{_ViewPorts}}){
	  my $nw = $vp->{W} + ($x-$pw) * $vp->{W}/$pw;
	  my $nx0 = $vp->{X0} + ($x-$pw) * $vp->{X0}/$pw;
	  my $nh = $vp->{H} + ($y-$ph) * $vp->{H}/$ph;
	  my $ny0 = $vp->{Y0} + ($y-$ph) * $vp->{Y0}/$ph;
	  print "reshape: resizing viewport to $nx0,$ny0,$nw,$nh\n" if($PDL::Graphics::TriD::verbose);
	  $vp->resize($nx0,$ny0,$nw,$nh);
	  $vp->{Impl}{highlight}{IsValid} = 0;
	}
}

sub twiddle {
  my($this,$getout,$dontshow) = @_;
  my (@e);
  my $quit;
  if ($PDL::Graphics::TriD::offline) {
    $PDL::Graphics::TriD::offlineindex ++;
    $this->display();
    require PDL::IO::Pic;
    wpic($this->read_picture(),"PDL_$PDL::Graphics::TriD::offlineindex.jpg");
    return;
  }
  return if $getout and $dontshow and !$this->{_GLObject}->event_pending;
  $getout //= !($PDL::Graphics::TriD::keeptwiddling && $PDL::Graphics::TriD::keeptwiddling);
  $this->display();
  TWIDLOOP: while(1) {
    print "EVENT!\n" if $PDL::Graphics::TriD::verbose;
    my $hap = 0;
    my $gotev = 0;
    if ($this->{_GLObject}->event_pending or !$getout) {
      @e = $this->{_GLObject}->next_event;
      $gotev=1;
    }
    print "e= ".join(",",$e[0]//'undef',@e[1..$#e])."\n" if $PDL::Graphics::TriD::verbose;
    if (@e and defined $e[0]) {
      if ($e[0] eq 'visible') {
        $hap = 1;
      } elsif ($e[0] eq 'reshape') {
        print "CONFIGNOTIFE\n" if $PDL::Graphics::TriD::verbose;
        $this->reshape(@e[1,2]);
        $hap=1;
      } elsif ($e[0] eq 'destroy') {
        print "DESTROYNOTIFE\n" if $PDL::Graphics::TriD::verbose;
        $quit = 1;
        $hap=1;
        $this->close;
        last TWIDLOOP;
      } elsif ($e[0] eq 'keypress') {
        print "KEYPRESS: '$e[1]'\n" if $PDL::Graphics::TriD::verbose;
        if (lc($e[1]) eq "q") {
          $quit = 1;
          last TWIDLOOP if not $getout;
        }
        if (lc($e[1]) eq "c") {
          $quit = 2;
        }
        $hap=1;
      }
    }
    if ($gotev) {
      foreach my $vp (@{$this->{_ViewPorts}}) {
        if (defined($vp->{EHandler})) {
          $hap += $vp->{EHandler}->event(@e) || 0;
        }
      }
    }
    if (!$this->{_GLObject}->event_pending) {
           $this->display if $hap;
           last TWIDLOOP if $getout;
    }
    @e = ();
  }
  print "STOPTWIDDLE\n" if $PDL::Graphics::TriD::verbose;
  return $quit;
}

sub close {
  my ($this, $close_window) = @_;
  print "CLOSE\n" if $PDL::Graphics::TriD::verbose;
  undef $this->{_GLObject};
  $PDL::Graphics::TriD::current_window = undef;
}

# Resize window.
sub doconfig {
	my($this,$x,$y) = @_;
	$this->reshape($x,$y);
	print "CONFIGURENOTIFY\n" if($PDL::Graphics::TriD::verbose);
}

sub domotion {
	my($this) = @_;
	print "MOTIONENOTIFY\n" if($PDL::Graphics::TriD::verbose);
}

sub display {
  my($this) = @_;
  return unless defined($this);
  $this->{_GLObject}->set_window; # for multiwindow support
  print "display: calling glClear()\n" if $PDL::Graphics::TriD::verbose;
  glClear(GL_COLOR_BUFFER_BIT|GL_DEPTH_BUFFER_BIT);
  for my $vp (@{$this->{_ViewPorts}}) {
    glPushAttrib(GL_TRANSFORM_BIT|GL_COLOR_BUFFER_BIT);
    glMatrixMode(GL_MODELVIEW);
    glPushMatrix();
    $vp->do_perspective();
    if ($vp->{Transformer}) {
      print "display: transforming viewport!\n" if $PDL::Graphics::TriD::verbose;
      $vp->{Transformer}->togl();
    }
    print "VALID $this=$this->{IsValid}\n" if $PDL::Graphics::TriD::verbose;
    if (!$vp->{IsValid}) {
      glpSetAutoCheckErrors(1);
      $vp->togl_setup;
      print "VALID1 $vp\n" if $PDL::Graphics::TriD::verbose;
      $vp->{IsValid} = 1;
    }
    $vp->togl;
    glMatrixMode(GL_MODELVIEW);
    glPopMatrix();
    glPopAttrib();
  }
  $this->{_GLObject}->swap_buffers;
  print "display: after SwapBuffers\n" if $PDL::Graphics::TriD::verbose;
}

# should this really be in viewport?
sub read_picture {
	my($this) = @_;
	my($w,$h) = @{$this}{qw/Width Height/};
	my $res = PDL->zeroes(PDL::byte,3,$w,$h);
	glPixelStorei(GL_UNPACK_ALIGNMENT,1);
	glPixelStorei(GL_PACK_ALIGNMENT,1);
        glReadPixels_c(0,0,$w,$h,GL_RGB,GL_UNSIGNED_BYTE,$res->make_physical->address_data);
	return $res;
}

######################################################################
######################################################################
# EVENT HANDLER MINIPACKAGE FOLLOWS!

package # hide from PAUSE
  PDL::Graphics::TriD::EventHandler;

use fields qw/X Y Buttons VP/;
sub new {
  my $class = shift;
  my $vp = shift;
  my $self = fields::new($class);
  $self->{X} = -1;
  $self->{Y} = -1;
  $self->{Buttons} = [];
  $self->{VP} = $vp;
  $self;
}

sub event {
  my($this,$type,@args) = @_;
  print "EH: ",ref($this)," $type (",join(",",@args),")\n" if $PDL::Graphics::TriD::verbose;
  return if !defined $type;
  my $retval;
  if ($type eq 'motion') {
    return if (my $but = $args[0]) < 0;
    print "MOTION $args[0]\n" if $PDL::Graphics::TriD::verbose;
    if ($this->{Buttons}[$but] and $this->{VP}{Active}) {
      print "calling ".($this->{Buttons}[$but])."->mouse_moved ($this->{X},$this->{Y},$args[1],$args[2])...\n" if $PDL::Graphics::TriD::verbose;
      $retval = $this->{Buttons}[$but]->mouse_moved(@$this{qw(X Y)}, @args[1,2]);
    }
    @$this{qw(X Y)} = @args[1,2];
  } elsif ($type eq 'buttonpress') {
    my $but = $args[0]-1;
    print "BUTTONPRESS $but\n" if $PDL::Graphics::TriD::verbose;
    @$this{qw(X Y)} = @args[1,2];
    $retval = $this->{Buttons}[$but]->ButtonPress(@args[1,2])
      if $this->{Buttons}[$but];
  } elsif ($type eq 'buttonrelease') {
    my $but = $args[0]-1;
    print "BUTTONRELEASE $but\n" if $PDL::Graphics::TriD::verbose;
    $retval = $this->{Buttons}[$but]->ButtonRelease($args[1],$args[2])
      if $this->{Buttons}[$but];
  } elsif ($type eq 'reshape') {
    # Kludge to force reshape of the viewport associated with the window -CD
    print "ConfigureNotify (".join(",",@args).")\n" if $PDL::Graphics::TriD::verbose;
    print "viewport is $this->{VP}\n" if $PDL::Graphics::TriD::verbose;
  }
  $retval;
}

sub set_button {
  my($this,$butno,$act) = @_;
  $this->{Buttons}[$butno] = $act;
}

######################################################################
######################################################################
# VIEWPORT MINI_PACKAGE FOLLOWS!

package # hide from PAUSE
  PDL::Graphics::TriD::ViewPort;

use OpenGL::Modern qw/
  glLoadIdentity glMatrixMode glOrtho glFrustum
  glViewport
  GL_MODELVIEW GL_PROJECTION
/;

unshift @PDL::Graphics::TriD::GL::Highlight::ISA, qw(PDL::Graphics::TriD::Lines);
sub PDL::Graphics::TriD::GL::Highlight::primitive {OpenGL::Modern::GL_LINE_LOOP}

sub highlight {
  my ($vp) = @_;
  if (!defined $vp->{Impl}{highlight}) {
    my $hl = $vp->{Impl}{highlight} = PDL::Graphics::TriD::GL::Highlight->new(
      PDL->new(PDL::float, [[0,0,0], [$vp->{W},0,0], [$vp->{W},$vp->{H},0],
        [0,$vp->{H},0]]),
      PDL->new(PDL::float, [1,1,1]),
      { LineWidth => 4 },
    );
    $hl->togl_setup;
    $hl->{IsValid} = 1;
  }
  if (!(my $hl = $vp->{Impl}{highlight})->{IsValid}) {
    $hl->{Points} .= PDL->new(PDL::float, [[0,0,0], [$vp->{W},0,0],
      [$vp->{W},$vp->{H},0], [0,$vp->{H},0]]),
    $hl->togl_setup;
    $hl->{IsValid} = 1;
  }
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity();
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  glOrtho(0,$vp->{W},0,$vp->{H},-1,1);
  $vp->{Impl}{highlight}->togl;
}

use constant PI => 3.1415926535897932384626433832795;
use constant FOVY => 40.0;
use constant ANGLE => FOVY / 360 * PI;
use constant TAN => sin(ANGLE)/cos(ANGLE);
use constant { zNEAR => 0.1, zFAR => 200000.0 };
use constant fH => TAN * zNEAR;
sub do_perspective {
  my($this) = @_;
  print "do_perspective ",$this->{W}," ",$this->{H} ,"\n" if $PDL::Graphics::TriD::verbose;
  print Carp::longmess() if $PDL::Graphics::TriD::verbose>1;
  unless($this->{W}>0 and $this->{H}>0) {return;}
  $this->{AspectRatio} = (1.0*$this->{W})/$this->{H};
  glViewport(@$this{qw(X0 Y0 W H)});
  $this->highlight if $this->{Active};
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity();
  # https://stackoverflow.com/questions/12943164/replacement-for-gluperspective-with-glfrustrum
  my $fW = fH * $this->{AspectRatio};
  glFrustum(-$fW, $fW, -fH, fH, zNEAR, zFAR);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity ();
}

package PDL::Graphics::TriD::GL;

use strict;
use warnings;
use PDL::Graphics::TriD::Window qw();
use PDL::Options;

$PDL::Graphics::TriD::verbose //= 0;

# This is a list of all the fields of the opengl object
#use fields qw/Display Window Context Options GL_Vendor GL_Version GL_Renderer/;

=head1 NAME

PDL::Graphics::TriD::GL - PDL TriD OpenGL interface using POGL

=head1 DESCRIPTION

This module provides the glue between the Perl
OpenGL functions and the API defined by the internal
PDL::Graphics::OpenGL one. It also supports any
miscellaneous OpenGL or GUI related functionality to
support PDL::Graphics::TriD refactoring.

It defines an interface that subclasses will conform to, implementing
support for GLFW, GLUT, X11+GLX, etc, as the mechanism for creating windows
and graphics contexts.

=head1 CONFIG

Defaults to using L<OpenGL::GLFW> - override by setting the environment
variable C<POGL_WINDOW_TYPE> to C<glut>, C<x11> , or the default is C<glfw>.

=head2 new

=for ref

Returns a new OpenGL object.

=for usage

  new($class,$options,[$window_type])

  Attributes are specified in the $options field; the 3d $window_type is optionsl. The attributes are:

=over

=item x,y - the position of the upper left corner of the window (0,0)

=item width,height - the width and height of the window in pixels (500,500)

=back

Allowed 3d window types, case insensitive, are:

=over

=item glfw - use Perl OpenGL bindings and GLFW windows (no Tk)

=item glut - use Perl OpenGL bindings and GLUT windows (no Tk)

=item x11  - use Perl OpenGL (POGL) bindings with X11

Additional attributes for X11 windows:

=over

=item parent - the parent under which the new window should be opened (root)

=item mask - the user interface mask (StructureNotifyMask)

=item attributes - attributes to pass to glXChooseVisual

=back

=back

=cut

sub new {
  my($class,$options,$window_obj) = @_;
  my $opt = PDL::Options->new($class->default_options);
  $opt->incremental(1);
  $opt->options($options) if(defined $options);
  my $p = $opt->options;
  bless {Options => $p}, ref($class)||$class;
}

=head2 default_options

default options for object oriented methods

=cut

sub default_options {
  {
    x => 0,
    y => 0,
    width => 500,
    height => 500,
  }
}

=head2 swap_buffers

OO interface to swapping frame buffers

=cut

sub swap_buffers {
  my ($this) = @_;
  die "swap_buffers: got object with inconsistent _GLObject info\n";
}

=head2 set_window

OO interface to setting the display window (if appropriate)

=cut

sub set_window {
  my ($this) = @_;
}

=head1 AUTHOR

Chris Marshall, C<< <devel dot chm dot 01 at gmail.com> >>

=head1 BUGS

Bugs and feature requests may be submitted through the PDL GitHub
project page at L<https://github.com/PDLPorters/pdl/issues> .

=head1 SUPPORT

PDL uses a mailing list support model.  The Perldl mailing list
is the best for questions, problems, and feature discussions with
other PDL users and PDL developers.

To subscribe see the page at L<http://pdl.perl.org/?page=mailing-lists>

=head1 ACKNOWLEDGEMENTS

TBD including PDL TriD developers and POGL developers...thanks to all.

=head1 COPYRIGHT & LICENSE

Copyright 2009 Chris Marshall.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1;
